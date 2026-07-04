#include "printf.h"
#include "trap.h"
#include "mul.h"
#include "div.h"

#define FRAC_BIT 10

#define RD_ADDR 135106448
#define RD_SIZE_D0 1
#define RD_SIZE_D1 1
#define RD_SIZE_D2 28
#define RD_SIZE_D3 28

#define WEIGHT_ADDR 134217728
#define WEIGHT_SIZE_D0 20
#define WEIGHT_SIZE_D1 1
#define WEIGHT_SIZE_D2 5
#define WEIGHT_SIZE_D3 5

#define WR_ADDR 135108240
#define WR_SIZE_D0 1
#define WR_SIZE_D1 20
#define WR_SIZE_D2 12
#define WR_SIZE_D3 12

#define KERN_ATTR_CONV_PAD 0
#define KERN_ATTR_CONV_STRIDE 1
#define KERN_ATTR_POOL_PAD 0
#define KERN_ATTR_POOL_KERN_SIZE 2
#define KERN_ATTR_POOL_STRIDE 2

//MMIO register address of DNN accelerator
#define GPIO_START_ADDR    0x60030000
#define GPIO_DONE_ADDR     0x60030008

struct size_vec4
{
	unsigned d0;
	unsigned d1;
	unsigned d2;
	unsigned d3;
};

struct mem_addr
{
	unsigned rd_addr;
	unsigned weight_addr;
	unsigned wr_addr;
};

int mul(short a, short b)
{
#ifndef USE_MUL
	int ans = mul_ll(a, b);
#else
	int ans = a * b;
#endif
	return ans;
}

struct mem_addr addr = {RD_ADDR, WEIGHT_ADDR, WR_ADDR};
struct size_vec4 rd_size = {RD_SIZE_D0, RD_SIZE_D1, RD_SIZE_D2, RD_SIZE_D3};
struct size_vec4 wr_size = {WR_SIZE_D0, WR_SIZE_D1, WR_SIZE_D2, WR_SIZE_D3};
struct size_vec4 weight_size = {WEIGHT_SIZE_D0, WEIGHT_SIZE_D1, WEIGHT_SIZE_D2, WEIGHT_SIZE_D3};

struct size_vec4 conv_size;

extern char _binary_data_result_bin_start[];
extern char _binary_data_result_bin_size[];

void convolution()
{
	short *in = (short *)addr.rd_addr;
	short *weight = (short *)addr.weight_addr;
	short *out = (short *)addr.wr_addr;

	unsigned input_fm_w = rd_size.d3;
	unsigned input_fm_h = rd_size.d2;

	unsigned pad = KERN_ATTR_CONV_PAD;
	unsigned pad_len = pad << 1;

	unsigned conv_out_w = rd_size.d3 - weight_size.d3 + pad_len;
	unsigned conv_out_h = rd_size.d2 - weight_size.d2 + pad_len;

	unsigned stride = KERN_ATTR_CONV_STRIDE;

	conv_out_w = div(conv_out_w, stride);
	conv_out_h = div(conv_out_h, stride);

	conv_out_w++;
	conv_out_h++;

	conv_size.d0 = wr_size.d0;
	conv_size.d1 = wr_size.d1;
	conv_size.d2 = conv_out_h;
	conv_size.d3 = conv_out_w;

	int oc, oh, ow, kh, kw;
	// 每个卷积核的真实长度：1个bias + 25个weight = 26个short
	int kernel_len = 1 + weight_size.d2 * weight_size.d3; 

	for (oc = 0; oc < weight_size.d0; oc++) {
		for (oh = 0; oh < conv_out_h; oh++) {
			for (ow = 0; ow < conv_out_w; ow++) {
				
				// 获取偏置并转换为32位定点数作为初始累加值
				int sum = ((int)weight[oc * kernel_len]) << FRAC_BIT;
				
				for (kh = 0; kh < weight_size.d2; kh++) {
					for (kw = 0; kw < weight_size.d3; kw++) {
						int ih = oh * stride - pad + kh;
						int iw = ow * stride - pad + kw;
						
						// 处理 padding 边界
						if (ih >= 0 && ih < input_fm_h && iw >= 0 && iw < input_fm_w) {
							short in_val = in[ih * input_fm_w + iw];
							short w_val = weight[oc * kernel_len + 1 + kh * weight_size.d3 + kw];
							sum += mul(in_val, w_val);
						}
					}
				}
				
				// 结果右移恢复16位定点格式并保存
				out[oc * conv_out_h * conv_out_w + oh * conv_out_w + ow] = (short)(sum >> FRAC_BIT);
			}
		}
	}
}

void pooling()
{
	short *out = (short *)addr.wr_addr;
	short *in  = (short *)addr.wr_addr; // 读取卷积生成的中间数据

	unsigned input_fm_w = conv_size.d3;
	unsigned input_fm_h = conv_size.d2;

	unsigned pad = KERN_ATTR_POOL_PAD;
	unsigned pad_len = pad << 1;

	unsigned pad_w_test = conv_size.d3 - KERN_ATTR_POOL_KERN_SIZE;
	unsigned pad_h_test = conv_size.d2 - KERN_ATTR_POOL_KERN_SIZE;

	unsigned pool_out_w = pad_w_test + pad_len;
	unsigned pool_out_h = pad_h_test + pad_len;

	unsigned stride = KERN_ATTR_POOL_STRIDE;

	unsigned pad_w_test_remain = pad_w_test - mul(div(pad_w_test, stride), stride);
	unsigned pad_h_test_remain = pad_h_test - mul(div(pad_h_test, stride), stride);

	pool_out_w = div(pool_out_w, stride);
	pool_out_h = div(pool_out_h, stride);
	pool_out_w++;
	pool_out_h++;

	if ((!pad) && (pad_w_test_remain || pad_h_test_remain))
	{
		pool_out_w++;
		pool_out_h++;
	}

	int c, oh, ow, ph, pw;
	for (c = 0; c < conv_size.d1; c++) {
		for (oh = 0; oh < pool_out_h; oh++) {
			for (ow = 0; ow < pool_out_w; ow++) {
				
				// 16位有符号定点数最小值
				short max_val = -32768; 
				
				for (ph = 0; ph < KERN_ATTR_POOL_KERN_SIZE; ph++) {
					for (pw = 0; pw < KERN_ATTR_POOL_KERN_SIZE; pw++) {
						int ih = oh * stride - pad + ph;
						int iw = ow * stride - pad + pw;
						
						if (ih >= 0 && ih < input_fm_h && iw >= 0 && iw < input_fm_w) {
							short val = in[c * input_fm_h * input_fm_w + ih * input_fm_w + iw];
							if (val > max_val) {
								max_val = val;
							}
						}
					}
				}
				
				out[c * pool_out_h * pool_out_w + oh * pool_out_w + ow] = max_val;
			}
		}
	}
}

#ifdef USE_HW_ACCEL
#ifdef USE_HW_ACCEL
void launch_hw_accel()
{
	volatile int* gpio_start = (void*)(GPIO_START_ADDR);
	volatile int* gpio_done = (void*)(GPIO_DONE_ADDR);

	// 拉高START位启动加速器
	*gpio_start = 1;

	// 轮询等待DONE寄存器的第0位被拉高
	while ((*gpio_done & 1) == 0) {
		// Wait
	}

	// 任务完成后重置START寄存器
	*gpio_start = 0;
}
#endif
#endif

int comparing()
{
	char *out = (char *)addr.wr_addr;
	char *result = (char *)_binary_data_result_bin_start;

#ifdef USE_HW_ACCEL
	int count = (int)_binary_data_result_bin_size + 
		    (16 - WR_SIZE_D3) * 2 * WR_SIZE_D2 * WR_SIZE_D1;
#else
	int count = (int)_binary_data_result_bin_size;
#endif

	for (int i = 0, j = 0; i < count; i++)
	{
#ifdef USE_HW_ACCEL
		int alignment = i & 0x0000001f;
		if (alignment >= (WR_SIZE_D3 << 1))
			continue;
#endif
		if (*(out + i) != *(result + j))
		{
			printf("Failed! at address %x and %x with data %x and %x\n", out + i, result + j, *(out + i), *(result + j));
			return 1;
		}
		j++;
	}

	printf("Passed!\n");
	return 0;
}

static inline unsigned int read_cycle() {
    unsigned int cycle;
    asm volatile("csrr %0, mcycle" : "=r"(cycle));
    return cycle;
}

int main()
{

unsigned int cycle_start, cycle_end;

#ifdef USE_HW_ACCEL
	printf("Launching task...\n");
	cycle_start = read_cycle();
	launch_hw_accel();
	cycle_end = read_cycle();
#else
	printf("starting convolution\n");
	cycle_start = read_cycle();
	convolution();
	printf("starting pooling\n");
	pooling();
	cycle_end = read_cycle();
#endif

	int result = comparing();
	
	printf("benchmark finished\n");
	printf("Cycles cost: %u\n", cycle_end - cycle_start);

	if (result == 0) {
		hit_good_trap();
	} else {
		nemu_assert(0);
	}

	return 0;
}
