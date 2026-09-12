
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

void main()=>runApp(const App());

class App extends StatelessWidget{
 const App({super.key});
 @override Widget build(BuildContext c)=>MaterialApp(
  debugShowCheckedModeBanner:false,title:'BTC Radar',
  theme:ThemeData(brightness:Brightness.dark,useMaterial3:true,
   scaffoldBackgroundColor:const Color(0xff070a0f),
   colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xfff2a900),brightness:Brightness.dark)),
  home:const Home());
}
class Market{final double price,change;final List<double> p;Market(this.price,this.change,this.p);}
double sma(List<double>x,int n){n=math.min(n,x.length);return x.sublist(x.length-n).reduce((a,b)=>a+b)/n;}
double rsi(List<double>x,int n){if(x.length<=n)return 50;double g=0,l=0;for(int i=x.length-n;i<x.length;i++){final d=x[i]-x[i-1];if(d>0)g+=d;else l-=d;}if(l==0)return 100;final rs=(g/n)/(l/n);return 100-100/(1+rs);}
double score(List<double>x){if(x.length<200)return 50;final p=x.last,s50=sma(x,50),s200=sma(x,200),rr=rsi(x,14),a=(x.length>365?x.sublist(x.length-365):x).reduce(math.max),dd=p/a-1;double s=50;s+=(-(p/s200-1)*55).clamp(-22,22);s+=(-(p/s50-1)*18).clamp(-10,10);s+=((50-rr)*.42).clamp(-15,15);s+=((-dd-.15)*22).clamp(-8,10);return s.clamp(0,100);}
String state(int s){if(s<=20)return'DEEP BOTTOM WATCH';if(s<=35)return'ACCUMULATION';if(s<=55)return'NEUTRAL';if(s<=70)return'DISTRIBUTION WATCH';if(s<=85)return'HIGH TOP RISK';return'EXTREME TOP RISK';}
String action(int s){if(s<=35)return'Watch for staged buying and confirmation.';if(s>=78)return'Risk is elevated; consider staged profit-taking.';return'Wait for stronger confirmation.';}
class Api{static const b='https://api.coingecko.com/api/v3';Future<Market> load()async{final r=await Future.wait([http.get(Uri.parse('$b/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true')),http.get(Uri.parse('$b/coins/bitcoin/market_chart?vs_currency=usd&days=730&interval=daily'))]);if(r.any((x)=>x.statusCode!=200))throw Exception();final a=jsonDecode(r[0].body)['bitcoin'];final p=(jsonDecode(r[1].body)['prices']as List).map((z)=>(z[1]as num).toDouble()).toList();return Market((a['usd']as num).toDouble(),(a['usd_24h_change']as num).toDouble(),p);}}
class Home extends StatefulWidget{const Home({super.key});@override State<Home>createState()=>_Home();}
class _Home extends State<Home>{final api=Api();Market?m;bool loading=true;String?err;
 @override void initState(){super.initState();refresh();}
 Future<void>refresh()async{setState(()=>loading=true);try{final x=await api.load();setState(()=>{m=x,loading=false,err=null});}catch(_){setState(()=>{loading=false,err='Could not load BTC data. Check internet or API limits.'});}}
 String usd(double n)=>'\$${n.toStringAsFixed(0)}';Color cc(int s)=>s<=35?const Color(0xff4ade80):s<=55?const Color(0xfffacc15):s<=70?const Color(0xffff923c):const Color(0xfff87171);
 @override Widget build(BuildContext c){final s=m==null?50:score(m!.p);return Scaffold(appBar:AppBar(title:const Text('₿ BTC Radar 5.1',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:loading?null:refresh,icon:const Icon(Icons.refresh))]),body:RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(16),children:[
 if(loading)const Padding(padding:EdgeInsets.only(top:150),child:Center(child:CircularProgressIndicator()))
 else if(err!=null)Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[Text(err!,textAlign:TextAlign.center),const SizedBox(height:12),FilledButton(onPressed:refresh,child:const Text('Retry'))])))
 else ...[
  card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('BITCOIN / USD',style:TextStyle(letterSpacing:2,fontSize:12)),const SizedBox(height:8),Text(usd(m!.price),style:const TextStyle(fontSize:38,fontWeight:FontWeight.w900)),Text('${m!.change>=0?'+':''}${m!.change.toStringAsFixed(2)}% • 24h',style:TextStyle(color:m!.change>=0?Colors.greenAccent:Colors.redAccent,fontWeight:FontWeight.bold))])),
  const SizedBox(height:12),card(Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('RADAR SCORE',style:TextStyle(letterSpacing:2)),Text('${s.round()}/100',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900,color:cc(s.round())))]),const SizedBox(height:12),LinearProgressIndicator(value:s/100,minHeight:13,valueColor:AlwaysStoppedAnimation(cc(s.round()))),const SizedBox(height:14),Text(state(s.round()),style:TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:cc(s.round()))),const SizedBox(height:6),Text(action(s.round()),textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70))])),
  const SizedBox(height:12),Row(children:[Expanded(child:metric('Bottom bias','${(100-s).round()}%',Icons.south_rounded)),const SizedBox(width:10),Expanded(child:metric('Top risk','${s.round()}%',Icons.north_rounded))]),
  const SizedBox(height:12),card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('TECHNICAL FACTORS',style:TextStyle(letterSpacing:1.5,fontSize:12)),const SizedBox(height:10),Text('50D SMA: ${usd(sma(m!.p,50))}'),Text('200D SMA: ${usd(sma(m!.p,200))}'),Text('RSI(14): ${rsi(m!.p,14).toStringAsFixed(1)}')])),
  const SizedBox(height:12),card(const Text('SIGNAL RULES\n\n🟢 BUY WATCH  ≤35\n🟢 BUY CONFIRM CANDIDATE  ≤25\n🔴 SELL WATCH  ≥78\n🚨 SELL CONFIRM CANDIDATE  ≥85\n\nThis standalone version uses market/technical data only. Advanced on-chain and ETF factors are intentionally disabled until Backend is enabled.',style:TextStyle(height:1.5))),
  const SizedBox(height:12),card(const Text('IMPORTANT\n\nThis is a decision-support tool, not a guaranteed prediction system or financial advice. Thresholds should be validated with historical backtesting before real-money use.',style:TextStyle(color:Colors.white70,height:1.5)))
 ] ]));}
 Widget card(Widget w)=>Card(child:Padding(padding:const EdgeInsets.all(18),child:w));
 Widget metric(String a,String b,IconData i)=>card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(i),const SizedBox(height:8),Text(b,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w900)),Text(a,style:const TextStyle(color:Colors.white60,fontSize:12))]));
}
