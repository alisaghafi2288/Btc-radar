
import 'dart:convert';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'BTC Radar',
    theme: ThemeData(
      brightness: Brightness.dark, useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff070a0f),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xfff2a900), brightness: Brightness.dark),
    ),
    home: const Home(),
  );
}

class Market {
  final double price, change;
  final List<double> prices;
  final List<double> volumes;
  Market(this.price, this.change, this.prices, this.volumes);
}

// ---------- Technical indicators ----------

double sma(List<double> x, int n) {
  n = math.min(n, x.length);
  return x.sublist(x.length - n).reduce((a, b) => a + b) / n;
}

List<double> emaSeries(List<double> x, int n) {
  final k = 2 / (n + 1);
  final out = <double>[x.first];
  for (int i = 1; i < x.length; i++) {
    out.add(x[i] * k + out[i - 1] * (1 - k));
  }
  return out;
}

double rsi(List<double> x, int n) {
  if (x.length <= n) return 50;
  double gains = 0, losses = 0;
  for (int i = x.length - n; i < x.length; i++) {
    final d = x[i] - x[i - 1];
    if (d > 0) gains += d; else losses -= d;
  }
  if (losses == 0) return 100;
  final rs = (gains / n) / (losses / n);
  return 100 - (100 / (1 + rs));
}

// MACD: returns (macd line, signal line, histogram) for the latest point
class Macd {
  final double macd, signal, hist;
  Macd(this.macd, this.signal, this.hist);
}

Macd macd(List<double> x) {
  if (x.length < 35) return Macd(0, 0, 0);
  final ema12 = emaSeries(x, 12);
  final ema26 = emaSeries(x, 26);
  final macdLine = <double>[];
  for (int i = 0; i < x.length; i++) {
    macdLine.add(ema12[i] - ema26[i]);
  }
  final signalLine = emaSeries(macdLine, 9);
  final m = macdLine.last, s = signalLine.last;
  return Macd(m, s, m - s);
}

// Volume trend: ratio of recent avg volume to longer avg volume
double volumeTrend(List<double> v) {
  if (v.length < 30) return 1.0;
  final recent = sma(v, 7);
  final base = sma(v, 30);
  if (base == 0) return 1.0;
  return recent / base;
}

// Bollinger Band position: where price sits within band, 0 = lower, 1 = upper
double bollingerPosition(List<double> x, int n) {
  if (x.length < n) return 0.5;
  final window = x.sublist(x.length - n);
  final mean = window.reduce((a, b) => a + b) / n;
  final variance = window.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
  final sd = math.sqrt(variance);
  if (sd == 0) return 0.5;
  final upper = mean + 2 * sd;
  final lower = mean - 2 * sd;
  final p = x.last;
  return ((p - lower) / (upper - lower)).clamp(0.0, 1.0);
}

// ---------- Composite radar score ----------

class ScoreBreakdown {
  final double score;
  final double trendComponent, rsiComponent, drawdownComponent, macdComponent, volumeComponent, bollingerComponent;
  ScoreBreakdown(this.score, this.trendComponent, this.rsiComponent,
      this.drawdownComponent, this.macdComponent, this.volumeComponent, this.bollingerComponent);
}

ScoreBreakdown radarScore(List<double> x, List<double> v) {
  if (x.length < 200) {
    return ScoreBreakdown(50, 0, 0, 0, 0, 0, 0);
  }
  final p = x.last, s50 = sma(x, 50), s200 = sma(x, 200), rr = rsi(x, 14);
  final year = x.length > 365 ? x.sublist(x.length - 365) : x;
  final high = year.reduce(math.max);
  final dd = p / high - 1;
  final m = macd(x);
  final volT = volumeTrend(v);
  final bbPos = bollingerPosition(x, 20);

  double base = 50;
  final trendComp = (-(p / s200 - 1) * 55).clamp(-22, 22) + (-(p / s50 - 1) * 18).clamp(-10, 10);
  final rsiComp = ((50 - rr) * .42).clamp(-15, 15);
  final ddComp = ((-dd - .15) * 22).clamp(-8, 10);
  // MACD: negative histogram (bearish momentum) pushes score down (buy side), positive pushes up
  final macdComp = (-(m.hist / (p * 0.01)) * 6).clamp(-8.0, 8.0);
  // Volume trend: rising volume on the move amplifies whichever direction we're leaning
  final volComp = ((volT - 1) * 10).clamp(-6.0, 6.0);
  // Bollinger: near lower band pulls score down (buy zone), near upper band pushes up
  final bbComp = ((bbPos - 0.5) * 20).clamp(-10.0, 10.0);

  double s = base + trendComp + rsiComp + ddComp + macdComp + volComp + bbComp;
  s = s.clamp(0, 100);
  return ScoreBreakdown(s, trendComp, rsiComp, ddComp, macdComp, volComp, bbComp);
}

String state(int s) {
  if (s <= 20) return 'DEEP BOTTOM WATCH';
  if (s <= 35) return 'ACCUMULATION';
  if (s <= 55) return 'NEUTRAL';
  if (s <= 70) return 'DISTRIBUTION WATCH';
  if (s <= 85) return 'HIGH TOP RISK';
  return 'EXTREME TOP RISK';
}

String action(int s) {
  if (s <= 25) return 'Strong buy zone forming; consider staged entries.';
  if (s <= 35) return 'Watch for staged buying and confirmation.';
  if (s >= 85) return 'Extreme risk; consider staged profit-taking now.';
  if (s >= 78) return 'Risk is elevated; consider staged profit-taking.';
  return 'Wait for stronger confirmation.';
}

// ---------- API ----------

class Api {
  static const b = 'https://api.coingecko.com/api/v3';
  // Paste your free CoinGecko Demo API key between the quotes below.
  static const apiKey = 'YOUR_API_KEY_HERE';

  Uri _u(String path, Map<String, String> params) {
    final all = {...params, if (apiKey.isNotEmpty && apiKey != 'YOUR_API_KEY_HERE') 'x_cg_demo_api_key': apiKey};
    return Uri.parse('$b$path').replace(queryParameters: all);
  }

  Future<Market> load() async {
    Future<http.Response> tryGet(Uri uri, {int retries = 2}) async {
      http.Response? last;
      for (int attempt = 0; attempt <= retries; attempt++) {
        try {
          final resp = await http.get(uri).timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200) return resp;
          last = resp;
          if (resp.statusCode == 429) {
            await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
            continue;
          }
          break;
        } catch (_) {
          await Future.delayed(Duration(seconds: 1 + attempt));
        }
      }
      return last ?? http.Response('', 0);
    }

    final priceUri = _u('/simple/price', {
      'ids': 'bitcoin',
      'vs_currencies': 'usd',
      'include_24hr_change': 'true',
    });
    final chartUri = _u('/coins/bitcoin/market_chart', {
      'vs_currency': 'usd',
      'days': '730',
      'interval': 'daily',
    });

    final r = await Future.wait([tryGet(priceUri), tryGet(chartUri)]);

    if (r.any((z) => z.statusCode != 200)) {
      final codes = r.map((z) => z.statusCode).toList();
      if (codes.contains(429)) {
        throw Exception('Rate limited by CoinGecko. Please wait a minute and retry, or add your free API key.');
      }
      throw Exception('API error (codes: $codes). Check internet connection.');
    }

    final a = jsonDecode(r[0].body)['bitcoin'];
    final raw = jsonDecode(r[1].body)['prices'] as List;
    final volRaw = jsonDecode(r[1].body)['total_volumes'] as List;
    final p = raw.map((z) => (z[1] as num).toDouble()).toList();
    final v = volRaw.map((z) => (z[1] as num).toDouble()).toList();
    return Market((a['usd'] as num).toDouble(),
        (a['usd_24h_change'] as num).toDouble(), p, v);
  }
}

// ---------- UI ----------

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final api = Api();
  Market? m;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final x = await api.load();
      if (!mounted) return;
      setState(() {
        m = x;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String usd(double n) => '\$${n.toStringAsFixed(0)}';

  Color scoreColor(int s) {
    if (s <= 35) return const Color(0xff4ade80);
    if (s <= 55) return const Color(0xfffacc15);
    if (s <= 70) return const Color(0xffff923c);
    return const Color(0xfff87171);
  }

  Widget card(Widget w) => Card(child: Padding(padding: const EdgeInsets.all(18), child: w));

  Widget metric(String a, String b, IconData i) => card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(i),
        const SizedBox(height: 8),
        Text(b, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        Text(a, style: const TextStyle(color: Colors.white60, fontSize: 12))
      ]));

  Widget chart(List<double> x) {
    final n = math.min(180, x.length), p = x.sublist(x.length - n);
    final lo = p.reduce(math.min), hi = p.reduce(math.max), span = math.max(1, hi - lo);
    return card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('180-DAY PRICE', style: TextStyle(letterSpacing: 1.5, fontSize: 12)),
      const SizedBox(height: 14),
      SizedBox(
          height: 180,
          child: LineChart(LineChartData(
            minY: lo - span * .05,
            maxY: hi + span * .05,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: [for (int i = 0; i < p.length; i++) FlSpot(i.toDouble(), p[i])],
                isCurved: true,
                dotData: const FlDotData(show: false),
                barWidth: 2.5,
                color: const Color(0xfff2a900),
              )
            ],
          )))
    ]));
  }

  Widget factorRow(String label, double value) {
    final positive = value >= 0;
    final color = positive ? Colors.redAccent : Colors.greenAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text('${positive ? '+' : ''}${value.toStringAsFixed(1)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = m == null ? null : radarScore(m!.prices, m!.volumes);
    final s = breakdown == null ? 50 : breakdown.score.round();
    final c = scoreColor(s);
    return Scaffold(
      appBar: AppBar(
          title: const Text('BTC Radar 5.3', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [IconButton(onPressed: loading ? null : refresh, icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (loading)
              const Padding(padding: EdgeInsets.only(top: 150), child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              card(Column(children: [
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: refresh, child: const Text('Retry'))
              ]))
            else if (m != null) ...[
              card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('BITCOIN / USD', style: TextStyle(letterSpacing: 2, fontSize: 12)),
                const SizedBox(height: 8),
                Text(usd(m!.price), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                Text('${m!.change >= 0 ? '+' : ''}${m!.change.toStringAsFixed(2)}% (24h)',
                    style: TextStyle(
                        color: m!.change >= 0 ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold))
              ])),
              const SizedBox(height: 12),
              card(Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('RADAR SCORE', style: TextStyle(letterSpacing: 2)),
                  Text('$s/100', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: c))
                ]),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: s / 100, minHeight: 13, valueColor: AlwaysStoppedAnimation<Color>(c)),
                const SizedBox(height: 14),
                Text(state(s), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c)),
                const SizedBox(height: 6),
                Text(action(s), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))
              ])),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: metric('Bottom bias', '${100 - s}%', Icons.south_rounded)),
                const SizedBox(width: 10),
                Expanded(child: metric('Top risk', '$s%', Icons.north_rounded))
              ]),
              const SizedBox(height: 12),
              card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TECHNICAL FACTORS', style: TextStyle(letterSpacing: 1.5, fontSize: 12)),
                const SizedBox(height: 10),
                Text('50D SMA: ${usd(sma(m!.prices, 50))}'),
                Text('200D SMA: ${usd(sma(m!.prices, 200))}'),
                Text('RSI(14): ${rsi(m!.prices, 14).toStringAsFixed(1)}'),
                Text('MACD histogram: ${macd(m!.prices).hist.toStringAsFixed(2)}'),
                Text('Volume trend (7d/30d): ${volumeTrend(m!.volumes).toStringAsFixed(2)}x'),
                Text('Bollinger position: ${(bollingerPosition(m!.prices, 20) * 100).toStringAsFixed(0)}%'),
              ])),
              if (breakdown != null) ...[
                const SizedBox(height: 12),
                card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('SCORE BREAKDOWN', style: TextStyle(letterSpacing: 1.5, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Text('Positive pushes toward sell risk, negative toward buy zone.',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 10),
                  factorRow('Trend (50/200 SMA)', breakdown.trendComponent),
                  factorRow('RSI(14)', breakdown.rsiComponent),
                  factorRow('Drawdown from 1y high', breakdown.drawdownComponent),
                  factorRow('MACD momentum', breakdown.macdComponent),
                  factorRow('Volume trend', breakdown.volumeComponent),
                  factorRow('Bollinger position', breakdown.bollingerComponent),
                ])),
              ],
              const SizedBox(height: 12),
              chart(m!.prices),
              const SizedBox(height: 12),
              card(const Text(
                  'SIGNAL RULES\n\n'
                  'BUY WATCH: score 35 or below\n'
                  'BUY CONFIRM CANDIDATE: score 25 or below\n'
                  'SELL WATCH: score 78 or above\n'
                  'SELL CONFIRM CANDIDATE: score 85 or above\n\n'
                  'This standalone mode combines trend, momentum, volume and volatility '
                  'signals purely from market data. On-chain and ETF flow factors are not included.',
                  style: TextStyle(height: 1.5))),
              const SizedBox(height: 12),
              card(const Text(
                  'IMPORTANT\n\n'
                  'This is a decision-support tool, not a guaranteed prediction system or financial advice.',
                  style: TextStyle(color: Colors.white70, height: 1.5)))
            ]
          ])),
    );
  }
}
