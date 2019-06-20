//////////////////////////////////////////////////////////////////////////////////
// Module Name:    usart_tx 
// 功能：串口发送数据
//////////////////////////////////////////////////////////////////////////////////
module usart_tx
(
	input clk,			 			// 50MHz主时钟
	input rst_n,		 			//低电平复位信号	
	
	input [7:0] mydata_o,  		//接收到的flash一个字节的数据
	input myvalid_o,				//接收到一个字节的数据拉高一次
	
	output reg tx_en,				//发送数据使能信号，高表示正在发送数据
	
	output rs232_tx				// RS232发送数据信号
);


//以下波特率分频计数值可参照上面的参数进行更改
`define		BPS_PARA		 433	//波特率为115200时的分频计数值
`define  	BPS_PARA_2	 216	//波特率为115200时的分频计数值的一半，用于数据采样


//----------------------------------------------------------------------
//----------------------------------------------------------------------
reg[12:0] cnt;			//分频计数···························
reg clk_bps_t;			//波特率时钟寄存器
wire clk_bpstx;
wire bps_starttx;

always @ (posedge clk or negedge rst_n)
begin
	 if(!rst_n)
		 begin
			 cnt <= 13'd0;
		 end 
	 else if( (cnt == `BPS_PARA) || (!bps_starttx) )
		 begin
			 cnt <= 13'd0;	//波特率计数清零
		 end 
	 else cnt <= cnt + 1'b1;			//波特率时钟计数启动
end

always @ (posedge clk or negedge rst_n)
begin
	if(!rst_n)
		clk_bps_t <= 1'b0;
	else if(cnt == `BPS_PARA_2) 
		clk_bps_t <= 1'b1;	// clk_bps_r高电平为接收数据位的中间采样点,同时也作为发送数据的数据改变点
	else 
		clk_bps_t <= 1'b0;
end
	
assign clk_bpstx = clk_bps_t; 
//----------------------------------------------------------------------
//----------------------------------------------------------------------


//检测myvalid_o的上升沿，用来触发串口发送数据
reg myvalid0, myvalid1, myvalid2;
wire pose_myvalid;
always @ (posedge clk or negedge rst_n)
begin	
	if(!rst_n) 
		begin
			myvalid0 <= 1'b0;
			myvalid1 <= 1'b0;
			myvalid2 <= 1'b0;
		end
		
	else 
		begin
			myvalid0 <= myvalid_o;   
			myvalid1 <= myvalid0;
			myvalid2 <= myvalid1;
		end
end
assign pose_myvalid = myvalid1 & ~myvalid2;
//----------------------------------------------------------------------
//----------------------------------------------------------------------




//---------------------------------------------------------
reg[7:0] tx_data;	//待发送数据的寄存器
reg bps_start_t;
reg[5:0] num;

always @ (posedge clk or negedge rst_n) 
	begin
		if(!rst_n) 
			begin
				bps_start_t <= 1'b0;   
				tx_en <= 1'b0;     //发送数据使能信号
			end
			
		else if( pose_myvalid )      //启动串口发送数据
			begin	
				bps_start_t <= 1'b1;  
				tx_en <= 1'b1;		//进入发送数据状态中		
				tx_data <= mydata_o;
			end		
			
		else if(num == 5'd10)
			begin						//数据发送完成，复位
				bps_start_t <= 1'b0;
				tx_en <= 1'b0;
			end
	end

assign bps_starttx = bps_start_t;


//----------------------------------------------------------------------
//----------------------------------------------------------------------

reg rs232_tx_r;

always @ (posedge clk or negedge rst_n) begin
	if(!rst_n)
    	begin
			num <= 5'd0;
			rs232_tx_r <= 1'b1;
		end
	else if(tx_en)   //发送标志置高有效可以发送
		begin
			if(clk_bpstx)	
				begin
					num <= num+1'b1;
					case (num)
						4'd0: rs232_tx_r <= 1'b0; 	//发送起始位
						4'd1: rs232_tx_r <= tx_data[0];	//发送bit0
						4'd2: rs232_tx_r <= tx_data[1];	//发送bit1
						4'd3: rs232_tx_r <= tx_data[2];	//发送bit2
						4'd4: rs232_tx_r <= tx_data[3];	//发送bit3
						4'd5: rs232_tx_r <= tx_data[4];	//发送bit4
						4'd6: rs232_tx_r <= tx_data[5];	//发送bit5
						4'd7: rs232_tx_r <= tx_data[6];	//发送bit6
						4'd8: rs232_tx_r <= tx_data[7];	//发送bit7
						4'd9: rs232_tx_r <= 1'b1;	//发送结束位
					 	default: rs232_tx_r <= 1'b1;
					endcase
				end
			else if(num==5'd10) num <= 5'd0;	//复位
		end
end

assign rs232_tx = rs232_tx_r;

endmodule


