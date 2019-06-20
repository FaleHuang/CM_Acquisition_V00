module CM_Acquisition_V00
(
    input          CLK,
	 input          RSTn,
	 input  		    rx_data,


    output flash_clk,                 //spi flash clock 
	 output flash_cs,                  //spi flash cs 
	 
	 inout                   IO_qspi_io0         , // QPI总线输入/输出信号线
	 inout                   IO_qspi_io1         , // QPI总线输入/输出信号线
	 inout                   IO_qspi_io2         , // QPI总线输入/输出信号线
	 inout                   IO_qspi_io3,
	 
	 
	 output [3:0] led,
	 
	 output  rs232_tx
	 

);


wire [7 :0] rx_data_ino;	//串口数据连接
wire [7 :0] flash_cmd;
wire [23:0] flash_addr;
wire [4 :0] cmd_type;
wire [7 :0] mydata_o;
wire [15:0] I_status_reg;
wire myvalid_o;


wire clock25M;
wire Done_Sig;
wire tx_en;
wire spi_state;
wire rx_int;



flash_spi U1
(
		  .clk				(CLK),
		  .rst_n				(RSTn),
	     .flash_clk		(flash_clk ),
		  .flash_cs			(flash_cs ), 
		  
		  .IO_qspi_io0		(IO_qspi_io0),
		  .IO_qspi_io1		(IO_qspi_io1),
		  .IO_qspi_io2		(IO_qspi_io2),
		  .IO_qspi_io3		(IO_qspi_io3),
		 
		  
		  .clock25M			( clock25M ),          //input clock
		  .flash_rstn		( RSTn ),              //input reset 
		  .cmd_type			( cmd_type ),          // flash command type		  
		  .Done_Sig			( Done_Sig ),          //output done signal
		  .flash_cmd		( flash_cmd ),         // input flash command 
		  .flash_addr		( flash_addr ),        // input flash address 
		  .mydata_o			( mydata_o ),          // output flash data 
		  .myvalid_o		( myvalid_o ),         // output flash data valid 
		  .I_status_reg 	(I_status_reg),
		  
		  .tx_en				(tx_en) 
	  
);


//串口接收数据模块
usart_rx			usart_rx   
(		
	.clk					(CLK),
	.rst_n				(RSTn),
	
	.rx_int				(rx_int),
	.rx_data		  		(rx_data),
	.rx_data_o			(rx_data_ino)
);


//串口发送数据模块	
usart_tx			usart_tx  //发送数据模块
(
	.clk					(CLK),	
	.rst_n				(RSTn),

	.mydata_o			(mydata_o),           // output flash data 
   .myvalid_o			(myvalid_o),         // output flash data valid 
	
	.tx_en				(tx_en),	
	
	.rs232_tx     	 	(rs232_tx)
);


//指令判别处理模块
cmd_process     cmd_process
(
	.clk					(CLK),	
	.rst_n				(RSTn),

	.rx_int        	(rx_int),
	.rx_data_o			(rx_data_ino),
	
	.flash_cmd			(flash_cmd),         // output flash command 
	.flash_addr			(flash_addr),        // output flash address 
	.cmd_type			(cmd_type),
	.I_status_reg 		(I_status_reg),
	
	.clock25M			(clock25M),           //input clock
	
	.Done_Sig			(Done_Sig),
	
	.led					(led)
);


endmodule
































