# BTC Radar 5.3

Standalone Flutter Bitcoin radar app. Uses live price and market-chart data from
CoinGecko to compute a composite signal score (0-100) combining:

- 50-day and 200-day moving average trend
- RSI (14-day)
- Drawdown from the 1-year high
- MACD momentum
- Volume trend (7-day vs 30-day average)
- Bollinger Band position

The score maps to a plain-language state (Deep Bottom Watch, Accumulation,
Neutral, Distribution Watch, High Top Risk, Extreme Top Risk) and a suggested
action. A breakdown card shows exactly how much each factor is contributing.

## Setup

Open lib/main.dart and find the line:

    static const apiKey = 'YOUR_API_KEY_HERE';

Replace YOUR_API_KEY_HERE with a free CoinGecko Demo API key (sign up at
coingecko.com) to avoid rate-limit errors. The app works without a key too,
but the public tier is limited to about 5 to 15 calls per minute.

## Build

GitHub Actions: Actions -> Build BTC Radar APK -> Run workflow.
The generated APK will appear as a build artifact.

This is a decision-support tool only, not financial advice.
