//////////////////////////////////////////////////////////////////////////////////
// Module Name:    flash_spi 
//////////////////////////////////////////////////////////////////////////////////
module flash_spi(
						input 				clk,             	//50M主时钟
						input 				rst_n,					//复位信号
						
                  output 				flash_clk,
						output reg 			flash_cs,
						
						
						inout             IO_qspi_io0   , // QPI总线输入/输出信号线
						inout             IO_qspi_io1   , // QPI总线输入/输出信号线
						inout             IO_qspi_io2   , // QPI总线输入/输出信号线
						inout             IO_qspi_io3   , // QPI总线输入/输出信号线

                  input 				clock25M,
						input 				flash_rstn,
						
						input		  [15:0]	I_status_reg,		//写入flash状态寄存器的值
						
						input 	  [4:0]  cmd_type,		//指令状态指示
						
						input 	  [7 :0] flash_cmd, 	 	//写入flash的指令
						input 	  [23:0] flash_addr,		//写入flash的地址
						
						input					tx_en,			//此位高表示串口正在发送数据，拉低表示可以继续传输	
						
						output reg 	 		Done_Sig,		//flash完成一次的标志位
						output reg [7:0] 	mydata_o,
						output				myvalid_o

						);
						
	

// QSPI Flash IO输入输出状态控制寄存器
reg         R_qspi_io0          ;
reg         R_qspi_io1          ;
reg         R_qspi_io2          ;
reg         R_qspi_io3          ; 
reg         R_qspi_io0_out_en   ;
reg         R_qspi_io1_out_en   ;
reg         R_qspi_io2_out_en   ;
reg         R_qspi_io3_out_en   ;
	
// QSPI IO方向控制
assign IO_qspi_io0     =   R_qspi_io0_out_en ? R_qspi_io0 : 1'bz ;                
assign IO_qspi_io1     =   R_qspi_io1_out_en ? R_qspi_io1 : 1'bz ;                
assign IO_qspi_io2     =   R_qspi_io2_out_en ? R_qspi_io2 : 1'bz ;                
assign IO_qspi_io3     =   R_qspi_io3_out_en ? R_qspi_io3 : 1'bz ; 
//	

	
//----------------------------------------------------------------			
reg 		myvalid; 				//字节传输完成标志
reg 		spi_clk_en	= 1'b0;	//flash时钟使能信号
assign 	myvalid_o	= myvalid;
assign 	flash_clk 	= spi_clk_en ? clock25M:1'b0;	
//----------------------------------------------------------------

	
	
//----------------------------------------------------------------
//----------------------------------------------------------------
reg tx_en0, tx_en1, tx_en2;
wire neg_txen;
always @ (posedge clock25M or negedge rst_n) 
	begin
		if(!rst_n)
			begin
				 tx_en0 <= 1'b0;
				 tx_en1 <= 1'b0;
				 tx_en2 <= 1'b0;
			end
		else
			begin
				 tx_en0 <= tx_en;
				 tx_en1 <= tx_en0;
				 tx_en2 <= tx_en1;
			end
	end
assign neg_txen = ~tx_en1 & tx_en2;	//接收到tx_en下降沿后置高一个时钟周期
//----------------------------------------------------------------
//----------------------------------------------------------------


reg [7:0] mydata;

//flow
parameter idle					=	4'b0000;
parameter cmd_send			=	4'b0001;
parameter address_send		=	4'b0010;
parameter read_wait			=	4'b0011;
parameter write_data			=	4'b0101;
parameter write_state_reg	=	4'b0110;
parameter write_data_quad	=	4'b0111;
parameter r_dummy				=	4'b1000;
parameter read_wait_quad	= 	4'b1001;
parameter cmd_send_qual		= 	4'b1010;
parameter address_send_qual= 	4'b1011;
parameter finish_done		=	4'b1111;
parameter Data 				=	8'b1100_1111;


parameter T_DIVECE_ID		= 4'b0000;


reg [3:0] 	spi_state;
reg [7 :0]  cmd_reg;
reg [23:0]  address_reg;

reg [7 :0]  write_bits_cnt;					//写bit计数，写入一个bit加1
reg [7 :0]  read_bits_cnt;   					//读取bit计数，读取一个bit加1
reg [8 :0]  write_bytes_cnt;    				//写入字节计数，写一个字节加1
reg [8 :0]  read_bytes_cnt;  					//读取字节计数，读一个字节加1

reg [8 :0]  read_num;
reg [15:0]	R_status_reg;						//状态寄存器

reg data_come;  		//准备单通道采集
reg data_come_quad;
reg keep_state_acq;	//采集8bit后，采集的各状态保持
reg read_finish;

wire [7:0]	R_data_reg;

//发送读flash命令
always @(negedge clock25M)
begin
	if(!flash_rstn)
		begin
			flash_cs			<=	1'b1;		
			spi_state		<=	idle;
			cmd_reg			<=	0;
			address_reg		<=	0;
			spi_clk_en		<=	1'b0;                //SPI clock输出不使能
			write_bits_cnt	<=	8'd0;
			write_bytes_cnt<=	0;
			read_num			<=	0;	
			address_reg		<=	0;
			Done_Sig			<=	1'b0;
			data_come		<=	1'b0;
			data_come_quad	<=	1'b0;
		end
	else
		begin
		case(spi_state)
			idle: //000
			begin	//idle 状态		  
					spi_clk_en	<=	1'b0;
					flash_cs		<=	1'b1;
					
					cmd_reg		<=	flash_cmd;
					address_reg	<=	flash_addr;
					R_status_reg	<=	I_status_reg;
					Done_Sig		<=	1'b0;
					R_qspi_io3_out_en      <=   1'b0; 		// 设置IO_qspi_io3为高阻
					R_qspi_io2_out_en      <=   1'b0; 		// 设置IO_qspi_io2为高阻
					R_qspi_io1_out_en      <=   1'b0; 		// 设置IO_qspi_io1为高阻
					R_qspi_io0_out_en      <=   1'b0; 		// 设置IO_qspi_io0为高阻
					
					if(cmd_type[4] == 1'b1)	//bit4为命令请求,高表示操作命令请求
						begin  	
							R_qspi_io0_out_en	<=	1'b1;
							spi_state		<=	cmd_send;
							write_bits_cnt	<=	8'd7;		
							write_bytes_cnt<=	0;
							read_num			<=	0;
						end
			end
			
			cmd_send:	//0001
			begin //发送命令状态	
				spi_clk_en			<=	1'b1;             //flash的SPI clock输出
				R_qspi_io0_out_en	<=	1'b1;					//设置IO_qspi_io0为输出
				flash_cs				<=	1'b0;             //cs拉低
				
				if(write_bits_cnt > 8'd0) 
					begin                          //如果cmd_reg还没有发送完
						R_qspi_io0		<= cmd_reg[write_bits_cnt];  //发送bit7~bit1位
						write_bits_cnt	<=	write_bits_cnt - 1'd1;						
					end				
				else 
					begin                                 
						R_qspi_io0		<= cmd_reg[0];
						
						if ((cmd_type[3:0] == 4'b0001) || (cmd_type[3:0] == 4'b0010) || (cmd_type[3:0] == 4'b1010))	//如果是Write Enable/disable instruction,写使能或者不使能；进入QPI模式
							begin    
								spi_state <= finish_done;
//								Done_Sig		<=	1'b1;
							end	
							
						else if (cmd_type[3:0]==4'b0011)		//如果是read register1
							begin    
								spi_state		<=	read_wait;
								write_bits_cnt	<=	8'd7;
								read_num			<=	1;				//接收一个数据
							end	
							
						else if(cmd_type[3:0]==4'b0100)		//wirter register,跳转至单线写状态寄存器
							begin
								spi_state		<=	write_state_reg;
								write_bits_cnt	<=	8'd15;
							end 
						
						//如果是sector erase 0101, 单线页编程page program0110, 单线读数据read data0111,
						//read device ID 0000,    四线页编程1000，             四线读取命令1001，这些命令后都需要发送一个地址
						//
						else if( (cmd_type[3:0]==4'b0101)||
								   (cmd_type[3:0]==4'b0110)||
									(cmd_type[3:0]==4'b0111)||
									(cmd_type[3:0]==4'b1000)||
									(cmd_type[3:0]==4'b1001)||
									(cmd_type[3:0]==4'b0000))
							begin	                          	       
								spi_state			<=	address_send;
								write_bits_cnt	<=	8'd23;
							end
					end
			end
			
			//发送flash address	
			address_send:	//0010
			begin 
				R_qspi_io0_out_en		<=	1'b1;
				
				if(write_bits_cnt > 0)  
					begin                                  //如果cmd_reg还没有发送完
						R_qspi_io0		<=	address_reg[write_bits_cnt];		//发送bit23~bit1位
						write_bits_cnt	<=	write_bits_cnt - 8'd1;							
					end				
				else 
					begin                                       
						R_qspi_io0		<=	address_reg[0];	//发送bit0
						
						//如果是sector erase 0101, 单线页编程page program0110, 单线读数据read data0111,
						//read device ID 0000,    四线页编程1000，             四线读取命令1001，这些命令后都需要发送一个地址
						if(cmd_type[3:0]==4'b0000)				//如果是读Device ID
							begin                
								 spi_state	<=	read_wait;
								 read_num	<=	2;             //接收2个数据的Device ID
							end
							
						else if(cmd_type[3:0]==4'b0101)		//如果是	sector erase，扇区擦除指令，发完地址码即结束
							begin                     
								 spi_state	<=	finish_done;	
							end
							
						else if(cmd_type[3:0]==4'b0110)		//如果是单线page program	
							begin	              			
								 spi_state			<=	write_data;
								 write_bits_cnt	<=	8'd7;                       
							end
						         
						else if(cmd_type[3:0]==4'b0111)		//如果是单线read data	
							begin	              			
								 spi_state	<=	read_wait;
								 read_num	<=	256;                      
							end
												 
						else if(cmd_type[3:0]==4'b1000)		//如果是四线page program 
							begin
								 spi_state	<=	write_data_quad;
								 write_bits_cnt	<=	8'd7;      							 
							end		
		                     
						else if(cmd_type[3:0]==4'b1001)		//如果是四线read data,需要先等待8个dummy周期
							begin
								 spi_state	<=	r_dummy;
								 read_num	<=	256;
								 write_bits_cnt	<=	8'd7; 
							end
					end
			end
			
			
			read_wait:	//0011,单线读等待模式
			begin      //等待flash数据读完成，完成后CS拉高结束
				  if(read_finish) 
					  begin
						  spi_state	<=	finish_done;
						  spi_clk_en<=	1'b0;
						  data_come	<=	1'b0;
						  keep_state_acq	<= 1'b0;
						  Done_Sig		<=	1'b1;
					  end
				  else
					  begin
						  if( ~myvalid )   //读取的过程中接收一个字节完成后flash的时钟暂停，等待串口发送完成之后继续
								begin
									spi_clk_en		<=	1'b1;
									data_come		<=	1'b1;  //读取就绪
									keep_state_acq	<= 1'b0;
								end
							else if( myvalid == 1'b1 && (~neg_txen))
								begin
									spi_clk_en		<= 1'b0;
									data_come		<=	1'b0;  //等待串口发送
									keep_state_acq	<= 1'b1;
								end
							else if( myvalid == 1'b1 && neg_txen /*&& (read_bytes_cnt < read_num)*/ ) 
								begin
									if(read_bytes_cnt < read_num)
										begin
											spi_clk_en		<= 1'b1;
										end
									else
										begin
											spi_clk_en		<= 1'b0;
										end
									data_come		<=	1'b1;  //读取就绪
									keep_state_acq	<= 1'b0;
									R_qspi_io1_out_en   <=  1'b0;  //端口切换可能导致接收卡死，故此处注释
								end
						end
					
			end	
			
			write_data: 	//0101
			begin    //写flash block数据
				if( write_bytes_cnt < 256) 
					begin                      // program 256 byte to flash
						if(write_bits_cnt > 8'd0)	//如果data还没有发送完
							begin                       
								R_qspi_io0		<=	write_bytes_cnt[write_bits_cnt];           //发送bit7~bit1位
								write_bits_cnt	<=	write_bits_cnt - 1'd1;						
							end
						else 
							begin                              
								R_qspi_io0			<=	write_bytes_cnt[0];         //发送bit0
								write_bits_cnt		<=	7;
								write_bytes_cnt	<=	write_bytes_cnt + 1'b1;
							end
					end
							
				else 
					begin
						 spi_state	<=	finish_done;   //存储完成置位
						 spi_clk_en<=1'b0;
					end
			end
			
			write_state_reg:	//0110写寄存器状态
			begin
				R_qspi_io0_out_en		<=	1'b1;
				if(write_bits_cnt > 8'd0)  
					begin                                 //如果cmd_reg还没有发送完
						R_qspi_io0		<=	R_status_reg[write_bits_cnt];		//发送bit15~bit1位
						write_bits_cnt	<=	write_bits_cnt - 8'd1;							
					end				
				else 
					begin                                        //发送bit0
						R_qspi_io0		<=	R_status_reg[0];
						spi_state	<=	finish_done; 
					end
			end
			
			write_data_quad://0111
			begin
				R_qspi_io0_out_en   <=  1'b1    ;   // 设置IO0为输出
				R_qspi_io1_out_en   <=  1'b1    ;   // 设置IO1为输出
				R_qspi_io2_out_en   <=  1'b1    ;   // 设置IO2为输出
				R_qspi_io3_out_en   <=  1'b1    ;   // 设置IO3为输出 
				
				if(write_bytes_cnt == 9'd256)
					begin
						spi_state	<=	finish_done; 
						spi_clk_en		<=	1'b0;          //SPI clock输出不使能
					end 
					
				else 
					begin
						if(write_bits_cnt == 8'd3)
							begin
								write_bytes_cnt<=	write_bytes_cnt + 1'b1;
								write_bits_cnt	<=	8'd7;
								R_qspi_io3     <=  write_bytes_cnt[3]  ; // 分别发送bit3
								R_qspi_io2     <=  write_bytes_cnt[2]  ; // 分别发送bit2
								R_qspi_io1     <=  write_bytes_cnt[1]  ; // 分别发送bit1
								R_qspi_io0     <=  write_bytes_cnt[0]  ; // 分别发送bit0
							end
						else 
							begin
								write_bits_cnt <= write_bits_cnt - 8'd4;
								R_qspi_io3     <=  write_bytes_cnt[write_bits_cnt - 8'd0]  ; // 分别发送bit7
								R_qspi_io2     <=  write_bytes_cnt[write_bits_cnt - 8'd1]  ; // 分别发送bit6
								R_qspi_io1     <=  write_bytes_cnt[write_bits_cnt - 8'd2]  ; // 分别发送bit5
								R_qspi_io0     <=  write_bytes_cnt[write_bits_cnt - 8'd3]  ; // 分别发送bit4
							end 
					end
			end 
			
			r_dummy://1000 四线读之前等待8个周期
			begin
				R_qspi_io3_out_en   <=  1'b0  ; 		// 设置IO_qspi_io3为高阻
				R_qspi_io2_out_en   <=  1'b0  ; 		// 设置IO_qspi_io2为高阻
				R_qspi_io1_out_en   <=  1'b0  ;		// 设置IO_qspi_io1为高阻
				R_qspi_io0_out_en   <=  1'b0  ; 		// 设置IO_qspi_io0为高阻  
				
				if(write_bits_cnt > 8'd0)
					begin
						write_bits_cnt <= write_bits_cnt - 8'd1;
					end
				else 
					begin
						spi_state	<=	read_wait_quad;
					end
			end 
			
			read_wait_quad://1001四线读等待模式
			begin
				if(read_finish)
					begin
						spi_clk_en<=	1'b0;					//flash的SPI clock输出失能
						data_come_quad	<=	1'b0;
					   keep_state_acq	<= 1'b0;
						Done_Sig		<=	1'b1;
						spi_state <= finish_done;
					end
				else
					begin
					   if( ~myvalid )   //读取的过程中接收一个字节完成后flash的时钟暂停，等待串口发送完成之后继续
							begin
								spi_clk_en		<=	1'b1;
								data_come_quad		<=	1'b1;  //读取就绪
								keep_state_acq	<= 1'b0;
							end
						else if( myvalid == 1'b1 && (~neg_txen))
							begin
								spi_clk_en		<= 1'b0;
								data_come_quad		<=	1'b0;  //等待串口发送
								keep_state_acq	<= 1'b1;
							end
						else if( myvalid == 1'b1 && neg_txen /*&& (read_bytes_cnt < read_num)*/ ) 
							begin
								if(read_bytes_cnt < read_num)
									begin
										spi_clk_en		<= 1'b1;
									end
								else
									begin
										spi_clk_en		<= 1'b0;
									end
								data_come_quad		<=	1'b1;  //读取就绪
								keep_state_acq		<= 1'b0;
								R_qspi_io1_out_en  <=  1'b0;
							end
					end
			end 
			
			cmd_send_qual://1010
			begin
				spi_clk_en			  <=	1'b1;              //flash的SPI clock输出
				R_qspi_io0_out_en   <=  1'b1    ;   // 设置IO0为输出
				R_qspi_io1_out_en   <=  1'b1    ;   // 设置IO1为输出
				R_qspi_io2_out_en   <=  1'b1    ;   // 设置IO2为输出
				R_qspi_io3_out_en   <=  1'b1    ;   // 设置IO3为输出 
				
				if(write_bytes_cnt == 1)
					begin
						spi_state	<=	address_send_qual; 
						spi_clk_en		<=	1'b0;          //SPI clock输出不使能
						write_bits_cnt	<=	8'd23;
					end 
					
				else 
					begin
						if(write_bits_cnt == 8'd3)
							begin
								write_bytes_cnt<=	write_bytes_cnt + 1'b1;
								write_bits_cnt	<=	8'd7;
								R_qspi_io3     <=  cmd_reg[3]  ; // 分别发送bit3
								R_qspi_io2     <=  cmd_reg[2]  ; // 分别发送bit2
								R_qspi_io1     <=  cmd_reg[1]  ; // 分别发送bit1
								R_qspi_io0     <=  cmd_reg[0]  ; // 分别发送bit0
							end
						else 
							begin
								R_qspi_io3     <=  cmd_reg[write_bits_cnt - 8'd0]  ; // 分别发送bit7
								R_qspi_io2     <=  cmd_reg[write_bits_cnt - 8'd1]  ; // 分别发送bit6
								R_qspi_io1     <=  cmd_reg[write_bits_cnt - 8'd2]  ; // 分别发送bit5
								R_qspi_io0     <=  cmd_reg[write_bits_cnt - 8'd3]  ; // 分别发送bit4
								write_bits_cnt <= write_bits_cnt - 8'd4;
							end 
					end
			end 
			
			address_send_qual://1011
			begin
				if(write_bits_cnt > 3)  
					begin                                  //如果cmd_reg还没有发送完
						R_qspi_io3     <=  address_reg[write_bits_cnt - 8'd0]  ; // 分别发送bit3
						R_qspi_io2     <=  address_reg[write_bits_cnt - 8'd1]  ; // 分别发送bit2
						R_qspi_io1     <=  address_reg[write_bits_cnt - 8'd2]  ; // 分别发送bit1
						R_qspi_io0     <=  address_reg[write_bits_cnt - 8'd3]  ; // 分别发送bit0
						write_bits_cnt	<=	write_bits_cnt - 8'd4;		
					end				
				else 
					begin                                       
						R_qspi_io3     <=  address_reg[3]  ; // 分别发送bit3
						R_qspi_io2     <=  address_reg[2]  ; // 分别发送bit2
						R_qspi_io1     <=  address_reg[1]  ; // 分别发送bit1
						R_qspi_io0     <=  address_reg[0]  ; // 分别发送bit0
						spi_state	<=	write_data_quad;
					end
			end 
			
			finish_done:	//1111
			begin   //flash操作完成
				  flash_cs		<=	1'b1;
				  spi_clk_en	<=	1'b0;
				  Done_Sig		<=	1'b1;
				  spi_state		<=	idle;
				  R_qspi_io0_out_en    <=  1'b0;
				  R_qspi_io1_out_en    <=  1'b0;
				  R_qspi_io2_out_en    <=  1'b0;
				  R_qspi_io3_out_en    <=  1'b0;
			end
			default:spi_state	<=	idle;
			endcase		
		end
end









/////////////////////////
//接收flash数据	
////////////////////////
always @(posedge clock25M)
begin
	if(!flash_rstn)
		begin
			read_bytes_cnt <= 0;
			read_bits_cnt  <=	0;
			read_finish 	<=	1'b0;
			myvalid			<=	1'b0;
			mydata			<=	0;
			mydata_o			<=	0;
		end
	else if(data_come) //单通道接收 
		begin
			if(read_bytes_cnt < read_num) 
				begin  //接收数据			  
					if(read_bits_cnt < 7)  //接收一个byte的bit0~bit6	
						begin    	  
							myvalid			<=	1'b0;
							mydata			<=	{mydata[6:0],IO_qspi_io1};
							read_bits_cnt	<=	read_bits_cnt	+	1'b1;
						end
					else  
						begin
							myvalid		<=	1'b1;          //一个byte数据有效,此时将数据给串口，停止flash_clk,保持CS拉低
							mydata_o		<=	{mydata[6:0],IO_qspi_io1};
							read_bits_cnt		<=	0;
							read_bytes_cnt	<=	read_bytes_cnt + 1'b1;
						end
				end
			else 
				begin //表示此次读取完成
					 read_bytes_cnt	<=	0;
					 read_finish		<=	1'b1;
					 mydata_o			<= 8'd0;
					 mydata				<=	0;
					 myvalid				<=	1'b0;
				end
		end
		
	else if(data_come_quad)	//四通道接收
		begin
			if(read_bytes_cnt < read_num) 
				begin
					if(read_bits_cnt < 8'd1)  //接收一个byte的前4位
						begin    	  
							myvalid			<=	1'b0;
							mydata			<=	{mydata[3:0],IO_qspi_io3,IO_qspi_io2,IO_qspi_io1,IO_qspi_io0};//接收前四位
							read_bits_cnt	<=	read_bits_cnt	+	1'b1;
						end
						
					else 
						begin
							myvalid			<=	1'b1;
							mydata_o			<=	{mydata[3:0],IO_qspi_io3,IO_qspi_io2,IO_qspi_io1,IO_qspi_io0};//接收后四位
							read_bits_cnt	<=	0;
							read_bytes_cnt	<=	read_bytes_cnt + 1'b1;
						end 
				end 
			else
				begin
					read_bytes_cnt	<=	0;
					read_finish		<=	1'b1;
					mydata_o			<= 8'd0;
					mydata			<=	0;
					myvalid			<=	1'b0;
				end 
		end
	
	else if( keep_state_acq == 1'b1)
		begin
			 read_bytes_cnt	<=	read_bytes_cnt;
			 read_bits_cnt		<=	read_bits_cnt;
			 read_finish		<=	read_finish;
			 myvalid				<=	myvalid;
			 mydata				<=	mydata;
		end
		
	else 
		begin
			 read_bytes_cnt	<=	0;
			 read_bits_cnt		<=	0;
			 read_finish		<=	1'b0;
			 myvalid				<=	1'b0;
			 mydata				<=	0;
		end
end	

		
endmodule

















