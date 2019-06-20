//////////////////////////////////////////////////////////////////////////////////
// Module Name:    usart_rx 
// 功能：串口接收数据
//////////////////////////////////////////////////////////////////////////////////
module usart_rx
(
	 input clk,             	//50M主时钟
	 input rst_n,					//复位信号
	 
	 input rx_data,         	//接收到的串口信号
	 
	 output reg rx_int,       	//接收数据中断信号,接收到数据期间始终为高电平
	 output [7:0]  rx_data_o 	//将1字节的数据传输出去
);
	

/*
//串口波特率分频
parameter 	bps9600 		= 5207,	//波特率为9600bps
			 	bps19200 	= 2603,	//波特率为19200bps
				bps38400 	= 1301,	//波特率为38400bps
				bps57600 	= 867,	//波特率为57600bps
				bps115200	= 433;	//波特率为115200bps
				bps921600   = 53;    //波特率为921600bps

parameter 	bps9600_2 	= 2603,
				bps19200_2	= 1301,
				bps38400_2	= 650,
				bps57600_2	= 433,
				bps115200_2 = 216;  
				bps921600_2 = 26;
*/


//以下波特率分频计数值可参照上面的参数进行更改
`define		BPS_PARA		 433	//波特率为115200时的分频计数值
`define  	BPS_PARA_2	 216	//波特率为115200时的分频计数值的一半，用于数据采样
//------------------------------------------------------------------------


reg [12:0] cnt;			//分频计数
reg clk_bps_r;				//波特率时钟寄存器
wire clk_bpsrx;
wire bps_startrx;
	
//分频计数	
always @ (posedge clk or negedge rst_n)
begin
	 if(!rst_n)
		 begin
			 cnt <= 13'd0;
		 end 
	 else if( (cnt == `BPS_PARA) || (!bps_startrx) )
		 begin
			 cnt <= 13'd0;			//波特率计数清零
		 end 
	 else cnt <= cnt + 1'b1;	//波特率时钟计数启动
end
	 
//clk_bps_r高电平为接收数据位的中间采样点,同时也作为发送数据的数据改变点
always @ (posedge clk or negedge rst_n)
begin
	if(!rst_n) 
		clk_bps_r <= 1'b0;
	else if
		(cnt == `BPS_PARA_2) clk_bps_r <= 1'b1;	 // clk_bps_r高电平为接收数据位的中间采样点,同时也作为发送数据的数据改变点
	else 
		clk_bps_r <= 1'b0;
end
	
assign clk_bpsrx = clk_bps_r; 	
//------------------------------------------------------------------------	
	
	
	
	
//----------------------------------------------------------------
reg rx_data0,  rx_data1,  rx_data2,  rx_data3;	//接收数据寄存器，滤波用，防止毛刺信号
wire neg_rx_data;	    //表示数据线接收到下降沿，串口通信起始信号
  
always @ (posedge clk or negedge rst_n) 
	begin
		if(!rst_n)
			begin
				 rx_data0 <= 1'b0;
				 rx_data1 <= 1'b0;
				 rx_data2 <= 1'b0;
				 rx_data3 <= 1'b0;
			end
			
		else
			begin
				 rx_data0 <= rx_data;
				 rx_data1 <= rx_data0;
				 rx_data2 <= rx_data1;
				 rx_data3 <= rx_data2;
			end
	end
	
assign neg_rx_data = rx_data3 & rx_data2 & ~rx_data1 & ~rx_data0;	//接收到下降沿后neg_rx_Inte_Ti置高一个时钟周期
//------------------------------------------------------------------------


//**********************串口中断信号使能*********************//
reg bps_start_r;
reg[4:0] num;	   //移位次数

always @ (posedge clk or negedge rst_n)
begin
	if(!rst_n) 
		begin
			bps_start_r <= 1'b0;
			rx_int <= 1'b1;
		end
		
	else if(neg_rx_data)     //检测到起始信号
		begin		             //接收到串口接收线neg_rx_Inte_Ti的下降沿标志信号
			bps_start_r <= 1'b1;	   //启动串口准备数据接收
			rx_int <= 1'b1;			//接收数据中断信号使能，接收期间始终保持为高，指示是否在接收状态
		end
		
	else if(num==5'd10)
		begin		//接收完有用数据信息
			bps_start_r <= 1'b0;	   //数据接收完毕，释放波特率启动信号
			rx_int <= 1'b0;			//接收一个字节数据完毕中断信号关闭
		end
end

assign bps_startrx = bps_start_r;
//******************************************************************//


//----------------------------------------------------------------
reg[7:0] rx_data_r;		//串口接收数据寄存器，保存直至下一个数据来到
reg[7:0] rx_temp_data;	//当前接收数据寄存器

always @ (posedge clk or negedge rst_n)
begin
	if(!rst_n) 
		begin
			rx_temp_data <= 8'd0;
			num <= 5'd0;
			rx_data_r <= 8'd0;
		end
		
	else if(rx_int)
		begin	//接收数据处理
			if(clk_bpsrx)    //波特率的分频信号，分频周期的中间时刻点开始采样信号
				begin	//读取并保存数据,接收数据为一个起始位，8bit数据，1或2个结束位
					case (num)
						4'd1: rx_temp_data[0] <= rx_data;	//锁存第0bit
						4'd2: rx_temp_data[1] <= rx_data;	//锁存第1bit
						4'd3: rx_temp_data[2] <= rx_data;	//锁存第2bit
						4'd4: rx_temp_data[3] <= rx_data;	//锁存第3bit
						4'd5: rx_temp_data[4] <= rx_data;	//锁存第4bit
						4'd6: rx_temp_data[5] <= rx_data;	//锁存第5bit
						4'd7: rx_temp_data[6] <= rx_data;	//锁存第6bit
						4'd8: rx_temp_data[7] <= rx_data;	//锁存第7bit
						default: ;
					endcase
					num <= num + 1'b1;
				end
				
			else if(num == 5'd10)
				begin		               			//标准接收模式下只有1+8+1(2)=11bit的有效数据
					num <= 5'd0;						//接收到STOP位后结束,num清零
   				rx_data_r <= rx_temp_data;	   //把数据锁存到数据寄存器rx_data中			
				end
		end
end


assign rx_data_o = rx_data_r;	   //rx_data_o接收的积分时间数据

endmodule










