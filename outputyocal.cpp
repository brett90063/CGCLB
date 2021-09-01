#include <iostream>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <fstream>
#include <sstream>
#include <numeric>

using namespace std;

int main()
{
	vector<double> bushiba;
	string str;
	stringstream ss;

	fstream outputyo;
	outputyo.open("outputyo",ios::in);
	while(getline(outputyo,str))
	{
		if(str.size()>0)
		{
			double a;
			a = stod(str.c_str());
			bushiba.push_back(a);
			ss.clear();
		}
	}
	double max = bushiba[0];
	double min = bushiba[0];
	for(int i=0;i<bushiba.size();i++)
	{
		if(bushiba[i]>max)
		{
			max = bushiba[i];
		}
		if(bushiba[i]<min)
		{
			min = bushiba[i];
		}
	}
	for(int i=0;i<bushiba.size();i++)
	{
		if(bushiba[i]==max)
		{
			bushiba.erase(bushiba.begin()+i);
		}
	}
	for(int i=0;i<bushiba.size();i++)
	{
		if(bushiba[i]==min)
		{
			bushiba.erase(bushiba.begin()+i);
		}
	}
	double average = accumulate(bushiba.begin(),bushiba.end(),0.0)/bushiba.size();
	
	fstream frwd_speed;
	string s =  to_string(average);
	frwd_speed.open("frwd_speed",ios::out|ios::trunc);
	if(!frwd_speed)
	{
		cout << "fuckoff" << endl;
	}
	frwd_speed << s.data() << endl;




	outputyo.close();
	frwd_speed.close();


	

	return 0;
}
