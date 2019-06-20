//////////////////////////////////////////////////////////////////////////////////
// Module Name:    cmd_process
// 功能：对接收到的指令进行处理
//////////////////////////////////////////////////////////////////////////////////

/*
指令接收12个字节的指令，对于指令的处理不够严谨
1.仅能够处理12字节的指令
2.错误指令的判别未作相应反馈操作,错误指令会使程序进入未知循环，需要更正
3.数组使用完未及时清零
*/




module cmd_process
(
	input  clk,             	//50M主时钟
	input  rst_n,					//复位信号
	
	input  rx_int,		   	 	//接收数据中断信号,接收到数据期间始终为高电平,在该模块中利用它的下降沿来启动串口发送数据
	input  [7:0] rx_data_o,		//接收数据寄存器,需要发送的数据
	
	output reg [7:0]	flash_cmd,
	output reg [23:0]	flash_addr,
	output reg [4:0]  cmd_type,
	output reg [15:0] I_status_reg,
	
	output reg clock25M,
	
	input Done_Sig,
	
	output reg [3:0] led
);




///*******************************/
////产生25Mhz的SPI Clock	
///*******************************/	  
//always @ ( posedge clk )
//    if( !rst_n ) clock25M<=1'b0;
//	 else clock25M <= ~clock25M;
///*******************************/


/*******************************/
//产生12.5Mhz的SPI Clock	
/*******************************/	
reg [3:0] spiclk_cnt;
always @ ( posedge clk )
begin
	if( !rst_n )
		begin
			spiclk_cnt <= 4'd0;
		end
	else if(spiclk_cnt == 4'd1)
		begin
			spiclk_cnt <= 4'd0;
		end
	else 
		begin
			spiclk_cnt <=  spiclk_cnt + 4'd1;
		end 
end 


always @ ( posedge clk )
begin
	 if( !rst_n ) 
		begin
			clock25M<=1'b0;
		end
	 else if(spiclk_cnt == 4'd1)
		begin
			clock25M <= ~clock25M;
		end 
	 else 
		begin
			clock25M <= clock25M;
		end
end
//---------------------------------------------------------
   



//---------------------------------------------------------
reg rx_int0,rx_int1,rx_int2;	//rx_int信号寄存器，捕捉下降沿滤波用
wire neg_rx_int;	// rx_int下降沿标志位
always @ (posedge clk or negedge rst_n) 
	begin
		if(!rst_n) 
			begin
				rx_int0 <= 1'b0;
				rx_int1 <= 1'b0;
				rx_int2 <= 1'b0;
			end
		else 
			begin
				rx_int0 <= rx_int;   //rx_int为发送命令，这里检测发送命令，下降沿有效			
				rx_int1 <= rx_int0;
				rx_int2 <= rx_int1;
			end
	end
	
//捕捉到下降沿后，neg_rx_int拉高保持一个主时钟周期,表示1byte数据传输完成,将数据存入存储器
assign neg_rx_int =  ~rx_int1 & rx_int2;	
//---------------------------------------------------------




//定义一个memory的存储器,12*8bit的存储器
reg [7:0] cmdmema [11:0];


reg [5:0] cnt_mema;		//存储器的存储单元计数
reg [2:0] sto_sta; 	 	//接收状态指示
reg sto_end;        		 //存储完成标志
reg cmd_valid;
reg receive_finish; 	 	//接收并判断完成
reg error_flag;     	 	//指令错误标志位

reg [19:0] cnt_delay;	//延时计数

reg [3:0] j;

always @ (posedge clk or negedge rst_n)
begin
	if(!rst_n)
		begin
			cnt_mema <= 6'd0;
			sto_sta <= 3'b000;
			sto_end <= 1'b0;
			receive_finish <= 1'b0;
			error_flag <= 1'b0;
			cnt_delay <= 20'd0;
		end
		 
	else if( neg_rx_int || receive_finish )
		begin
			case(sto_sta)
				3'b000: //第1次接收不用判断
					begin
						if( cnt_mema < 6'd1) 
							begin
								cmdmema[cnt_mema] <= rx_data_o;
								cnt_mema <= cnt_mema + 6'd1;
								sto_sta <= 3'b001;
							end
					end
				3'b001://接收继续，验证上次的数据内容，是否已经接收到0D，如果接收到了，继续接收，切换
					begin
						if( cnt_mema >= 6'd1 && cnt_mema < 6'd11 && cmdmema[cnt_mema - 6'd1] != 8'd13)
							begin
								cmdmema[cnt_mema] <= rx_data_o;
								cnt_mema <= cnt_mema + 6'd1;
							end
							
						else if(cnt_mema <= 6'd11 && cmdmema[cnt_mema - 6'd1] == 8'd13)  //上次是0D，接收这次的数据，切换
							begin
								cmdmema[cnt_mema] <= rx_data_o;
								receive_finish <= 1'b1;  //接收完成，表示已经接收了12Byte
								sto_sta <= 3'b010;       //状态切换
							end
							
						else  //数据量超了，清空不再存储
							begin
								if(cnt_delay < 20'd99_9999)  //延时1ms
									begin
										receive_finish <= 1'b1; 
										cnt_delay <= cnt_delay + 20'd1;
									end
								else
									begin
										cnt_mema <= 6'd0;
										cnt_delay <= 20'd0;
										error_flag <= 1'b1;
										sto_sta <= 3'b011;
									end
							end
					end
				3'b010://这次接收到了0A，表示这组指令接收完成，进入指令判断，1ms内不再接收后续内容
					begin
						if(cmdmema[cnt_mema] == 8'd10)
							begin 
								if(cnt_delay < 20'd99_9999)  //延时1ms
									begin
										cnt_delay <= cnt_delay + 20'd1;
									end
								else
									begin
										cnt_delay <= 20'd0;
										sto_end	<= 1'b1;    //存储完成，进入指令判断
										cnt_mema	<= 6'd0;
										sto_sta	<= 3'b011;
									end
							end
						else if(cmdmema[cnt_mema] != 8'd10)  //已经接收到0D，但是这次不是0A，继续接收数据
							begin
								cnt_mema <= cnt_mema + 6'd1;
								receive_finish <= 1'b0;        //必须是由数据触发,此位置零
								sto_sta <= 3'b001;
							end
							
						else
							begin
								error_flag <= 1'b1;  //指令错误
								sto_end <= 1'b0;
								sto_sta <= 3'b011;
							end
					end
				3'b011:
					begin
						if(cmd_valid)
							begin
								sto_end <= 1'b0;
								sto_sta <= 3'b000;
								
								for(j = 4'b0; j <= 4'b11; j = j + 4'b1)
									begin
										cmdmema[j] <= 8'd0;
									end
								receive_finish <= 1'b0;  //接收完成是指一次代码从接收到验证结束
								error_flag <= 1'b0;	
							end
						else
							begin
								sto_sta <= sto_sta;
							end
					end
				default:
					begin
						sto_sta <= sto_sta;
					end
			endcase
		end
end
	
	
//command of flash
parameter	IDLE				=	8'h00;
parameter   R_DEVICE_ID 	= 	8'h90;	//读取ID指令
parameter   R_DEVICE_ID_Q 	= 	8'h94;	//四线读取ID指令
parameter	WR_ENABLE		=	8'h06;	//写使能
parameter   WR_DISABLE		=  8'h04; 	// Write Disable
parameter   ENTER_QPI		=  8'h38; 	// 进入QPI模式
parameter   EXIT_QPI			=  8'hFF; 	// 退出QPI模式
parameter   READ_STATUS1   =  8'h05; 	// READ STATUS REGISTER1
parameter   READ_STATUS2   =  8'h35; 	// READ STATUS REGISTER2
parameter   READ_STATUS3   =  8'h15; 	// READ STATUS REGISTER3
parameter   WR_STATUS1		=	8'h01;	//	WRITE STATUS REGISTER1
parameter   WR_STATUS2		=	8'h31;	//	WRITE STATUS REGISTER2
parameter   WR_STATUS3		=	8'h11;	//	WRITE STATUS REGISTER3
parameter	SEC_ERASE		=	8'h20;	//扇区擦除
parameter	SSPI_READ		=	8'h03;	//单线快速读
parameter	QUAD_READ		=	8'h6B;	//四线快速读
parameter	PAGE_PROGRAM	=	8'h02;	//PAGE PROGRAM
parameter	QPAGE_PROGRAM	=	8'h32;	//PAGE PROGRAM
parameter   BULK_ERASE		= 	8'h60;	//BULK Erase






//如果是sector erase 0101, 单线页编程page program0110, 单线读数据read data0111,
//read device ID 0000,    四线页编程1000，             四线读取命令1001，这些命令后都需要发送一个地址
//cmd_type
parameter   T_IDLE        			=   5'b0_0000 ; // IDLE
parameter   T_DIVECE_ID        	=   5'b1_0000 ; // read ID
parameter   T_WR_ENABLE        	=   5'b1_0001 ; // Write Enable
parameter   T_WR_DISABLE        	=   5'b1_0010 ; // Write Disable
parameter   T_READ_STATUS			=   5'b1_0011 ; // READ STATUS REGISTER            
parameter   T_WR_STATUS				=   5'b1_0100 ; // Write STATUS REGISTER          
parameter   T_SUB_ERASE				=   5'b1_0101 ; // SUBSECTOR Erase
parameter   T_PAGE_PROGRAM			=   5'b1_0110 ; // SINGLE PAGE PROGRAM             
parameter   T_READ					=   5'b1_0111 ; // SINGLE READ
parameter   T_QUAD_PROGRAM			=   5'b1_1000 ; // QUAD INPUT FAST PROGRAM
parameter   T_QUAD_READ				=   5'b1_1001 ; // QUAD OUTPUT FAST READ
parameter   T_BULK_ERASE        	=   5'b1_1011 ; // BULK Erase


//flow flash_state 
parameter	WR_IDLE			=	4'd10;	//结束状态
parameter	R_ID				=	4'd0;		//读取ID
parameter	EN_WR				=	4'd1;		//写使能
parameter	EN_ERASE			=	4'd2;		//擦除
parameter	EN_R_STATUS		= 	4'd3;	//读取状态寄存器		
parameter	DEN_WR			= 	4'd4;		//写失能
	

	
//指令判断
//C M 12 F W/R AD AD 00 00 0A 0D
 
reg [7:0]  R_cmd_type;
reg [23:0] R_flash_addr;
reg [4:0] state_process;
reg end_process;

always @ (posedge clk or negedge rst_n) 
begin
	if(!rst_n)
		 begin
			 led <= 4'b1111;
			 state_process<= 4'b0000;
		 end
//		 
	else if( sto_end )
		begin
			if(cmdmema[0] == 8'h43 && cmdmema[1] == 8'h4d && cmdmema[2] == 8'h0C /*&& cmdmema[3] == 8'h46*/)   //起始字符和字节长度正确进入判断
				begin
					if(cmdmema[3] == 8'h46)        //第四个字符为F（0x46）表示flash的指令
						begin 
							R_cmd_type <= cmdmema[6];
							R_flash_addr <= {cmdmema[7],cmdmema[8],cmdmema[9]};
							
							if(cmdmema[4] == 8'h52)  //第五个字符表示要对flash进行的操作，R（0x52）表示读
								begin	
									if(cmdmema[5] == 8'h49 || cmdmema[5] == 8'h53)	//第六个字符表示读写的具体操作，I（0x49），RI表示读ID;S(0x53),RS表示读寄存器
										begin
											if(end_process == 1'b1)
												begin	
													state_process <= 4'b0000;
												end
											else if(end_process == 1'b0)
												begin
													if(cmd_valid)
														begin
															state_process <= 4'b0000;
															led 		  <= 4'b0011;
														end
													else
														begin
															state_process <= 4'b0001;  //读取内容
															led 		  <= 4'b0001;
														end
												end
										end	
									else
										begin
											led 		  <= 4'b0000;
										end
								end
								
							else if(cmdmema[4] == 8'h57)	//保留判断其他指令，W（0x57）表示写，
								begin 
									if(cmdmema[5] == 8'h45 || cmdmema[5] == 8'h44 || cmdmema[5] == 8'h53 
										|| cmdmema[5] == 8'h51 || cmdmema[5] == 8'h4F)		//WE写使能；WD写使能；WS写状态寄存器；进入或者退出QPI
										begin
											if(end_process == 1'b1)
												begin	
													state_process <= 4'b0000;
												end
											else if(end_process == 1'b0)
												begin
													if(cmd_valid)
														begin
															state_process <= 4'b0000;
															led 		  <= 4'b0011;
														end
													else
														begin
															state_process <= 4'b0010; //写入内容
															led 		  <= 4'b0001;
														end
												end
										end
									else
										begin
											led 		  <= 4'b0000;
										end
								end
								
							else if(cmdmema[4] == 8'h51)	//保留判断其他指令，Q（0x51）表示写四线的模式操作
								begin
									if(cmdmema[5] == 8'h50 || cmdmema[5] == 8'h52)	//QP表示四线页编程,QR表示读
										begin
											if(end_process == 1'b1)
												begin	
													state_process <= 4'b0000;
												end
											else if(end_process == 1'b0)
												begin
													if(cmd_valid)
														begin
															state_process <= 4'b0000;
															led 		  <= 4'b0011;
														end
													else
														begin
															state_process <= 4'b0011; //进入QP模式选择模式
															led 		  <= 4'b0001;
														end
												end
										end 
								end 
							else if(cmdmema[4] == 8'h53)  //S表示单线操作或者擦除操作
								begin
									if(cmdmema[5] == 8'h50 || cmdmema[5] == 8'h52 || cmdmema[5] == 8'h45)	//SP表示单线页编程,SR表示单线读,SE表示整体擦除
										begin
											if(end_process == 1'b1)
												begin	
													state_process <= 4'b0000;
												end
											else if(end_process == 1'b0)
												begin
													if(cmd_valid)
														begin
															state_process <= 4'b0000;
															led 		  <= 4'b0011;
														end
													else
														begin
															state_process <= 4'b0100; //进入QP模式选择模式
															led 		  <= 4'b0001;
														end
												end
										end 
								end 
							
//							else if(cmdmema[4] == 8'h57) //保留判断其他指令，W（0x57）表示写，
//								begin 
//								end
								
							else
								begin
									led 		  <= 4'b0011;	//错误指示
									state_process <= 4'b0000;	
								end
						end
//					else if()	//保留判断其他指令
//						begin
//						end
					else 
						begin
							led <= 4'b0000;
						end 	
				end
			else if(cmdmema[0] == 8'h52 && cmdmema[1] == 8'h53)	//恢复指令，前两个字符分别为R（0x52）和S（0x53）
				begin
					if(end_process == 1'b1)
						begin	
							state_process <= 4'b0000;
						end
					else if(end_process == 1'b0)
						begin
							if(cmd_valid)
								begin
									state_process <= 4'b0000;
								end
							else
								begin
									state_process <= 4'b1111;
									led 		  <= 4'b1110;
								end
						end
				end
				
			else 
				begin
					state_process <= 4'b1010;
				end 
		end
		
	else if(error_flag == 1'b1)
		begin
			led <= 4'b0000;
		end
end 




reg [3:0] cmd_judge_state;//指令状态判断
always @ (posedge clk or negedge rst_n) 
begin
	if(!rst_n)
		 begin
			cmd_judge_state <= 4'd0;
			cmd_valid <= 1'b0;
			cmd_type	  <= 5'b00000;
			end_process	<= 1'b0;
		 end
		 
	else //if(cmd_judge_state == 4'b0000)
		begin
			case(cmd_judge_state)
				4'd0:
				begin
					if(state_process == 4'b0001)  //读取flash内容
						begin
							if(end_process)
								begin
									cmd_judge_state	<= 4'd0;
									cmd_valid <= 1'b0;
								end
							else
								begin
									cmd_judge_state	<= 4'd1;
									cmd_valid <= 1'b0;
								end
						end 
					
					else if(state_process == 4'b0010) //向flash写内容
						begin
							if(end_process)
								begin
									cmd_judge_state	<= 4'd0;
									cmd_valid <= 1'b0;
								end
							else 
								begin
									cmd_judge_state <= 4'd2;
									cmd_valid <= 1'b0;
								end 
						end
						
					else if(state_process == 4'b0011) //QP模式选择
						begin
							if(end_process)
								begin
									cmd_judge_state	<= 4'd0;
									cmd_valid <= 1'b0;
								end
							else 
								begin
									cmd_judge_state <= 4'd3;
									cmd_valid <= 1'b0;
								end 
						end
					
					else if(state_process == 4'b0100) //单线模式或者擦除选项
						begin
							if(end_process)
								begin
									cmd_judge_state	<= 4'd0;
									cmd_valid <= 1'b0;
								end
							else 
								begin
									cmd_judge_state <= 4'd4;
									cmd_valid <= 1'b0;
								end 
						end
					
					else if(state_process == 4'b1111) 
						begin
							if(end_process)
								begin
									cmd_judge_state	<= 4'd0;
									cmd_valid <= 1'b0;
								end
							else 
								begin
									cmd_judge_state <= 4'd15;
									cmd_valid <= 1'b0;
								end 
						end 
						
					else 
						begin
							cmd_judge_state <= cmd_judge_state;
							flash_cmd  <= 8'h00; 
							flash_addr <= 24'd0; 
							cmd_type	  <= 5'b00000;
							end_process	<= 1'b0;
						end 
				end
				
				4'd1://读取flash寄存器内容
				begin
					if(cmdmema[5] == 8'h49)
						begin
							flash_cmd	<= R_DEVICE_ID;
						end 
					else 
						begin
							if(R_cmd_type[7:5] == 3'b001)			//读寄存器1
								begin
									flash_cmd	<= READ_STATUS1;
								end
							else if(R_cmd_type[7:5] == 3'b010)	//读寄存器2
								begin
									flash_cmd	<= READ_STATUS2;
								end 
							else if(R_cmd_type[7:5] == 3'b011)	//读寄存器3
								begin
									flash_cmd	<= READ_STATUS3;
								end
							else 
								begin
									flash_cmd	<= READ_STATUS1;
								end
						end 
						
					cmd_type	  <= R_cmd_type[4:0];	//5'b10000;R_cmd_type
					flash_addr <= R_flash_addr;		//24'd0; R_flash_addr;
					
					if(Done_Sig)
						begin 
							cmd_judge_state <= 4'd0;
							end_process	<= 1'b1; 
							cmd_valid <= 1'b1;
						end 
					else cmd_judge_state <= cmd_judge_state;
				end
				
				4'd2://向flash写内容
				begin
					if(cmdmema[5] == 8'h45)//写使能
						begin
							flash_cmd	<=	WR_ENABLE;
						end 
					else if(cmdmema[5] == 8'h44)	//写失能
						begin
							flash_cmd	<=	WR_DISABLE;
						end 
					else if(cmdmema[5] == 8'h53)	//写寄存器
						begin
							if(R_cmd_type[7:5] == 3'b001)	//写寄存器1
								begin
									flash_cmd	<= WR_STATUS1;
								end 
							else if(R_cmd_type[7:5] == 3'b010)	//写寄存器2
								begin
									flash_cmd	<= WR_STATUS2;
								end 
							else if(R_cmd_type[7:5] == 3'b011)	//写寄存器3
								begin
									flash_cmd	<= WR_STATUS3;
								end 
							I_status_reg <= 16'h0002;
						end 
					else if(cmdmema[5] == 8'h51)//进入QPI模式
						begin
							flash_cmd	<= ENTER_QPI;
						end
					else if(cmdmema[5] == 8'h4F)//退出QPI模式
						begin
							flash_cmd	<= EXIT_QPI;
						end 
					cmd_type	  <= R_cmd_type[4:0];	//5'b10000;R_cmd_type
					flash_addr <= R_flash_addr;		//24'd0; R_flash_addr;	
					if(Done_Sig)
						begin 
							cmd_judge_state <= 4'd0;
							end_process	<= 1'b1; 
							cmd_valid <= 1'b1;
						end 
					else cmd_judge_state <= cmd_judge_state;
				end 
			
				4'd3:
				begin
					if(cmdmema[5] == 8'h50)			//四线页编程
						begin
							flash_cmd	<= QPAGE_PROGRAM;
						end
					else if(cmdmema[5] == 8'h52)	//四线读
						begin
							flash_cmd	<= QUAD_READ;
						end 
					
					cmd_type	  <= R_cmd_type[4:0];	//5'b10000;R_cmd_type
					flash_addr <= R_flash_addr;		//24'd0; R_flash_addr;
					if(Done_Sig)
						begin 
							cmd_judge_state <= 4'd0;
							end_process	<= 1'b1; 
							cmd_valid <= 1'b1;
						end 
					else cmd_judge_state <= cmd_judge_state;	
				end 
				
				4'd4://SP SR SE
				begin
					if(cmdmema[5] == 8'h50)			//单线页编程
						begin
							flash_cmd	<= PAGE_PROGRAM;
						end
					else if(cmdmema[5] == 8'h52)	//单线读
						begin
							flash_cmd	<= SSPI_READ;
						end 
					else if(cmdmema[5] == 8'h45)	//sector整体擦除
						begin
							flash_cmd	<= SEC_ERASE;
						end 
					 
					cmd_type	  <= R_cmd_type[4:0];	//5'b10000;R_cmd_type
					flash_addr <= R_flash_addr;		//24'd0; R_flash_addr;
					if(Done_Sig)
						begin 
							cmd_judge_state	<= 4'd0;
							end_process			<= 1'b1; 
							cmd_valid 			<= 1'b1;
						end 
					else cmd_judge_state <= cmd_judge_state;
				end 
				
				4'd15:
				begin
					cmd_judge_state <= 4'd0;
					end_process	<= 1'b1; 
					cmd_valid <= 1'b1;
				end 
				
				default:cmd_type	  <= 5'b00000;
			endcase
		end
end 

endmodule























