#!/usr/bin/perl

use warnings;
use Net::SSH::Perl;

my $host = "120.126.16.104";
my $root = "root";
my $user = "hsccl";
my $password = "spring67721";
my $CORENUM = 6;
my $TestTime = 1;
my $FileName = "0928_standard_4";
my $Method = (3,6,4);
my $CORENUM_IDX = $CORENUM-1;
my $pktinfo = $CORENUM."_1500_655360";
my $pktfile = $CORENUM."core_Random"; 
my $plname = $CORENUM."core_percent_655360";
my $frwd_kill_pid;

@percent = (0,10,20,30,40,50,60,70,80,90,100 );
#@percent = (90,91,92,93,94,95,96,97,98,99,100);
@method = (3,6,4);
@core = ( 1,2,3,4,5,6,7,8 );
@core_g = ( "0","0:1","0:1:2","0:1:2:3","0:1:2:3:4","0:1:2:3:4:5","0:1:2:3:4:5:6","0:1:2:3:4:5:6:7");

#test time
$time_start = $^T;
for($test_num = 0; $test_num < 1; $test_num++)
{

	($s,$m,$h,$d,$M)= localtime(time);	
	$first_load_file = 1;
	$filePos= " /home/hsccl/script_test/bushiba/".$plname."_2021";
	system("mkdir" .$filePos);
	
	#block per grid
	for($blocknum = 20; $blocknum < 21; $blocknum+=5){ #20
	#thread per block
	for($threadnum = 128; $threadnum < 129; $threadnum+=32){ #512
	#percent
	for($percent_i = 0; $percent_i < 11; $percent_i+=2){
	#core
	for($core_i = $CORENUM_IDX; $core_i < $CORENUM_IDX+1; $core_i++){
		$core_cur = $core[$core_i];
		$core_g_cur = $core_g[$core_i];
		$percent_cur =$percent [$percent_i];
		
		$output_str = $percent_cur;
		
		
		
		$pkt_name = $pktinfo."_".$percent_cur;
		$file_name = $FileName."_".$blocknum."_".$threadnum."_".$test_num;
		
		#method 3 6 4
		for($method_i = 2; $method_i < 3; $method_i++)
		{
			$method_cur = $method[$method_i];
			printf("\n core: $core_cur method: $method_cur  \n");
			&RUN;
			
			print "Final Speed :$speed \n";
			$output_str = $output_str."\t".$speed;
		}
		
		if( $first_load_file == 1 )
		{
			open(write_file,">".$filePos."/".$file_name);
			$first_load_file = 0;
		}
		else
		{
			open(write_file,">>".$filePos."/".$file_name);
		}
		
		my $info="$output_str";
		print write_file"$info\n";
		print "$info\n";
		
		close(write_file);
	}
	}
	}
	}
	print $d."_".$h."_".$m."_".$s."_2021\n";
}
$time_end = time();
$time = $time_end - $time_start;
printf "Total time : %.2f hours\n",($time/3600);
printf $file_name;

sub SENDER
{

	my $ssh = Net::SSH::Perl->new($host, protocol => '1,2' );
	$ssh->login($root, $password);

	#$ssh->cmd("cd /home/$user/PF_RING/userland/examples; ./pfsend -i zc:ens4f1 -f /home/$user/packet/Random/$pkt_name -r 0.1 -c -g 0");
	$ssh->cmd("nohup /home/$user/PF_RING/userland/examples/pfsend -i zc:ens4f1 -f /home/$user/packet/$pktfile/$pkt_name -r 0.1 -c -g 0 > /home/$user/PF_RING/userland/examples/nohup 2>&1 &");
	#$ssh->cmd("nohup /home/$user/PF_RING/userland/examples/pfsend -i zc:ens10f1 -f /home/$user/packet/Random/$pkt_name -r 0.1 -c -g 0 > /home/$user/PF_RING/userland/examples/nohup 2>&1 &");
		
	sleep(3);
	my($stdout, $stderr, $exit) = $ssh -> cmd("pidof pfsend");
	$ssh -> cmd("kill -9 $stdout");
	
	print "Running Packet: $pkt_name \n";
	print "Now Speed: $speed\n";
	$ssh->cmd("nohup /home/$user/PF_RING/userland/examples/pfsend -i zc:ens4f1 -f /home/$user/packet/$pktfile/$pkt_name -r $speed -c -g 0 > /home/$user/PF_RING/userland/examples/nohup 2>&1 &");
}

sub KILL_S
{
	my $ssh = Net::SSH::Perl->new($host,protocol => '1,2');
	$ssh->login($root, $password);
	my($stdout, $stderr, $exit) = $ssh->cmd("pidof pfsend");
	$ssh->cmd("kill -9 $stdout");
	print("kill pfsend\n");
	#print("KILL_$stdout\n");
	#print("KILL_S!\n");
	#print("$stdout");
}

sub KILL_R
{
	system("pidof zbounce > frwd_kill_pid");
	open(open_file,"frwd_kill_pid");
	while(<open_file>)
	{
	    chomp ; #Perl不會自動去掉結尾的CR/LF，跟C語言不同，所以要用chomp函數幫你去掉它
	    $frwd_kill_pid = $_;
	    print "kill zbounce: $_\n" ;
	}
	close(open_file);

 # my($frwd_kill_pid, $stderr, $exit) = system("pidof pfdnacluster_mt_rss_frwd_151020");

	system("kill -9 $frwd_kill_pid");
	#print ("KILL_$frwd_kill_pid\n");
	#print ("KILL_R!\n");
}

sub RUN
{

	sleep(1);
	system("sudo ethtool --set-channels ens4f0 combined ".$CORENUM);
	sleep(1);
	system("sudo ethtool --set-channels ens4f1 combined ".$CORENUM);
	sleep(1);

	$speed = 40;
	my $if_drop = 1;
	
	$speed10 = 400;
	$speed10half = 400;

	$break = 0;
	
	do
	{
		$trylongtime = 0;
RERUN:
		sleep(2);
		print "zbounce start\n";
		system("nohup ./zbounce -i zc:ens4f1 -o zc:ens4f0 -c 99 -g $core_g_cur -e $method_cur -n $core_cur -N 0 -s $blocknum -t $threadnum -j 1500 > /home/$user/PF_RING/userland/hpma_gpupre_adaptive_buffer/nohup 2>&1 &");
		sleep(15); #wait for PF_RING open ring
		&SENDER;
		sleep(15);
		
		&KILL_R;
		sleep(1);
		&KILL_S;
		sleep(2);
		
		if(open(open_file,"if_drop"))
		{
			while(<open_file>)
			{
				chomp ; #Perl不會自動去掉結尾的CR/LF，跟C語言不同，所以要用chomp函數幫你去掉它
				$if_drop = $_  ;
				#print $if_drop;
				print ("open if_drop:$if_drop\n");
			}
		}else{
			warn "Not find if_drop\n";
		}
		close(open_file);
		
		print "speed10half:$speed10half   speed10:$speed10\n";
		if( $speed10half > 0.5 )
		{
			$speed10half = $speed10half/2;
			
			if( $if_drop > 15000 ) #(($core_cur-1)*0.1) ) #微調
			{
				print "BpG: $blocknum  TpB: $threadnum  core:$core_cur  method: $method_cur  Drop:$if_drop IN  Speed:".($speed10/10)."\n";
				$speed10 -= $speed10half;
			}
			else  #if_drop==0
			{
				print "BpG: $blocknum TpB: $threadnum  core:$core_cur  method: $method_cur  NoDrop! IN  Speed:".($speed10/10)."\n";
				#if( $trylongtime == 0 ) #double check
				#{
				#	print "trylongtime\n";
				#	$speed10half = $speed10half*2;
				#	$trylongtime = 1;
				#	goto RERUN;
				#}
				
				if( $speed10 != 400 )
				{
					$speed10 += $speed10half;
					$trylongtime = 0;
				}
				else #if speed is 10 resend 1 time
				{
					#if( $first10 == 1 )
					#{
					#	$speed10half = 100;
					#	print "Repeat send!\n";
					#	$first10 = 0;
					#}
					#else 
					{
						$speed10half = 0;
						print "Speed is 40!\n";
					}
				}
			}
			if( $speed10half > 0 && $speed10half < 1 )
			{
				$speed10 = int($speed10+2);
			}
		}
		else
		{
			print "slice change ! \n";
			if($if_drop > 15000 )
			{		
				print "BpG: $blocknum TpB: $threadnum  core:$core_cur  method: $method_cur  Drop:$if_drop IN  Speed:".($speed10/10)."\n";
				$speed10 -=0.5;
			}
			else
			{
				if($speed10 >= 400)
				{
					$speed10 =400;
				}
				print "BpG: $blocknum  TpB: $threadnum  core:$core_cur  method: $method_cur  NoDrop!  IN  Speed:".($speed10/10)."\n";
				$break=1;
			}
		}
		$speed = $speed10/10;
		
	}while($break==0);
	
	print "Best speed : $speed\n";

}
