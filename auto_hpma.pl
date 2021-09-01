#!/usr/bin/perl

use warnings;
use Net::SSH::Perl;
#use diagnostics;

my $host = "120.126.16.104";
my $root = "root";
my $user = "hsccl";
my $password = "spring67721";
my $CORENUM = 3;
my $TestTime = 1;
my $buffertime = 1;
#my $FileName = "percent_".$CORENUM."c_originalhpma";
my $FileName = "CGC_persisetent_fastmemcpy_noeachbuffer";
my $CORENUM_IDX = $CORENUM-1;
#my $pktinfo = $CORENUM."_1500_655360"; #6_1500_655360
#my $pktfile = $CORENUM."core_Random"; #6core_Random

@percent = (0,10,20,30,40,50,60,70,80,90,100 );
@method = ("zbounce_hpma","zbounce_GPU");
@core = ( 0,1,2,3,4,5,6,7,8 );
@core_g = ( "0","0:1","0:1:2","0:1:2:3","0:1:2:3:4","0:1:2:3:4:5","0:1:2:3:4:5:6","0:1:2:3:4:5:6:7");


$time_start = $^T;
for($test_num = 0; $test_num < 1; $test_num++)
{
	$first_load_file = 1;
	#my $filePos = " /home/hsccl/script_test/bushiba/".$CORENUM."core_2021"; #6core_2021
	my $filePos = " /home/hsccl/PF_RING/userland/new_hpma_thirdcal/script_test/";
	system("mkdir".$filePos);

	#block per grid
	for($blocknum = 20; $blocknum < 21; $blocknum+=5){ #20
	#thread per block
	for($threadnum = 128; $threadnum < 129; $threadnum+=32){ #512
	#core
	#for($core_i = $CORENUM_IDX; $core_i < $CORENUM_IDX+1; $core_i++){
	for($core_i = 3; $core_i < 4; $core_i++){
		sleep(1);
		system("sudo ethtool --set-channels ens4f0 combined ".$core_i);
		sleep(1);
		system("sudo ethtool --set-channels ens4f1 combined ".$core_i);
		sleep(1);
	#percent
	for($percent_i = 0; $percent_i < 11; $percent_i+=1)
	{
		$core_cur = $core[$core_i]; #6
		$core_g_cur = $core_g[$core_i]; #0:1:2:3:4:5
		$percent_cur =$percent [$percent_i]; #0~100
		
		$output_str = $percent_cur;

		$pktinfo = $core_cur."_1500_655360";
		$pktfile = $core_cur."core_Random";
		$pkt_name = $pktinfo."_".$percent_cur; #6_1500_655360_0


		$file_name = $core_i."_".$FileName.$test_num;
		#$file_name = $percent_cur."_".$FileName.$test_num;

		#method zbounce_hpma zbounce_GPU
		for($method_i = 0; $method_i < 2; $method_i++)
		{
			$method_cur = $method[$method_i];
			printf("core: $core_cur method: $method_cur percent: ".($percent_i*10)."  \n");
			&RUN;
			sleep(2);
			system("sudo ./outputyocal"); #data process
			sleep(1);
			#system("sed -n 5p outputyo > frwd_speed");
			open(open_speed,"frwd_speed") or die "speed die: $!";
			while(<open_speed>)
			{
				chomp ($_);
				my $frwd_speed = $_;
				$output_str = $output_str."\t".$frwd_speed;
			}
			close(open_speed);

		}

		if( $first_load_file == 1 )
		{
			open(write_file,">".$filePos."/".$file_name) or die "WTF1";
			$first_load_file = 0;
		}
		else
		{
			open(write_file,">>".$filePos."/".$file_name) or die "WTF2";
		}

		my $info="$output_str";
		#print write_file "$info\n";
		print write_file $output_str."\n";
		print "$info\n";
		close(write_file);
	}
	}
	}
	}


}
$time_end = time();
$time = $time_end - $time_start;
printf "Total time : %.2f hours\n",($time/3600);

sub SENDER
{
	my $ssh = Net::SSH::Perl->new($host, protocol => '1,2' );
	$ssh->login($root, $password);

	$ssh->cmd("nohup /home/$user/PF_RING/userland/examples/pfsend -i zc:ens4f1 -f /home/$user/packet/$pktfile/$pkt_name -g 0 -r 40 -c > /home/$user/PF_RING/userland/examples/nohup 2>&1 &");
}

sub KILL_S
{
	my $ssh = Net::SSH::Perl->new($host,protocol => '1,2');
	$ssh->login($root, $password);
	my($stdout, $stderr, $exit) = $ssh->cmd("pidof pfsend");
	$ssh->cmd("kill -9 $stdout");
	print("kill_S!\n");
}

sub KILL_R
{
	system("pidof $method_cur > frwd_kill_pid");
	open(open_file,"frwd_kill_pid") or die "fuckyou: $!";
	while(<open_file>)
	{
		chomp ($_);
		my $frwd_kill_pidd = $_;
		system("kill -9 $frwd_kill_pidd");

	}
	close(open_file);

	print ("KILL_R!\n");
}

sub RUN
{
	sleep(2);
	print "$method_cur start\n";
	system("nohup ./$method_cur -i zc:ens4f1 -o zc:ens4f0 -c 99 -g $core_g_cur -n $core_cur -N 0 -s $blocknum -t $threadnum -r $buffertime -j 1500 > /home/$user/PF_RING/userland/new_hpma_thirdcal/nohup 2>&1 &");
	print "wait for ".($core_cur*3)." second\n";
	sleep($core_cur*3+1); #PF_RING open cluster
	&SENDER;
	sleep(8);

	&KILL_R;
	sleep(1);
	&KILL_S;
	sleep(2);

}





















