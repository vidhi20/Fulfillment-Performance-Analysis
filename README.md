# Fulfillment Performance Analysis

Where and why do e-commerce orders arrive late? An end-to-end fulfillment analytics project on the public Olist dataset (99,441 orders, 112,650 order items, 2016 to 2018).

## Questions
1. How reliable is the delivery network overall (on-time rate, time in each stage)?
2. Which fulfillment stage drives late orders: seller handling or carrier transit?
3. Where does lateness concentrate (regions, sellers)?

## Method
- **SQL (DuckDB) with CTEs, joins, and aggregations** in `analysis.sql`
- **Data validation first:** checked duplicates, missing delivery dates, and out-of-order timestamps; excluded 1,277 delivered orders with missing or out-of-order timestamps before analysis (95,201 delivered orders analyzed)
- Stage durations: purchase to approval, approval to carrier handoff (seller handling), carrier to customer (transit)
- Visuals in `fulfillment_dashboard.png`

## Key findings
| Metric | Result |
|---|---|
| On-time delivery rate | 93.2% (6,512 late orders) |
| Avg order-to-door time | 12.6 days (2.9 handling, 9.4 transit) |
| Transit time, late vs on-time orders | 27.9 vs 8.0 days (3.5x) |
| Late rate when seller missed ship-by limit | 20.9% vs 5.4% when on time (3.9x) |
| High-volume sellers missing ship-by limit 20%+ of the time | 34 of 231 |
| Worst states | MA 17.8% late, CE 14.0% (network 6.8%) |

## Recommendations
1. Flag orders at carrier handoff when the seller misses the ship-by limit; they are 3.9x more likely to arrive late.
2. Put the 34 chronically late high-volume sellers on a handling-time improvement plan.
3. Reset delivery estimates for northeast states where transit runs longest.

## Run it
```
pip install duckdb
python -c "import duckdb; c=duckdb.connect(); c.execute(open('analysis.sql').read()); print(c.execute('select * from kpis').fetchdf())"
```
Data: Olist Brazilian E-Commerce Public Dataset (github.com/olist/work-at-olist-data).
