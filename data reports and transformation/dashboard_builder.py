
"""Build a curated HTML dashboard from the generated forecast project outputs."""

from pathlib import Path
import json
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

base = Path('/mnt/data')
out_dir = base / 'curated_forecast_project'

catalog = pd.read_csv(out_dir/'dataset_catalog.csv')
bench_df = pd.read_csv(out_dir/'gld_model_benchmark.csv')
forecast_df = pd.read_csv(out_dir/'gld_30_business_day_forecast.csv', parse_dates=['Date'])
test_pred_df = pd.read_csv(out_dir/'gld_test_predictions.csv', parse_dates=['Date'])
gld = pd.read_csv(base/'gld_price_data.csv', parse_dates=['Date'])
bigmart = pd.read_csv(base/'bigmart_data.csv')
insurance = pd.read_csv(base/'insurance.csv')
with open(out_dir/'project_summary.json') as f:
    project_summary = json.load(f)

catalog_fig = px.scatter(
    catalog, x='rows', y='columns', size='missing_cells', color='domain',
    hover_name='dataset', log_x=True,
    title='Dataset Portfolio Map: Scale vs Feature Breadth'
)
catalog_fig.update_layout(height=420, margin=dict(l=20,r=20,t=50,b=20))

recent_hist = gld[gld['Date'] >= gld['Date'].max() - pd.Timedelta(days=700)].copy()
forecast_fig = go.Figure()
forecast_fig.add_trace(go.Scatter(x=recent_hist['Date'], y=recent_hist['GLD'], mode='lines', name='Historical GLD'))
forecast_fig.add_trace(go.Scatter(x=test_pred_df['Date'], y=test_pred_df['predicted_gld'], mode='lines', name='Backtest Prediction'))
forecast_fig.add_trace(go.Scatter(x=forecast_df['Date'], y=forecast_df['upper_95'], mode='lines', line=dict(width=0), hoverinfo='skip', showlegend=False))
forecast_fig.add_trace(go.Scatter(
    x=forecast_df['Date'], y=forecast_df['lower_95'], mode='lines',
    fill='tonexty', fillcolor='rgba(99,110,250,0.15)', line=dict(width=0),
    name='95% interval', hoverinfo='skip'
))
forecast_fig.add_trace(go.Scatter(
    x=forecast_df['Date'], y=forecast_df['forecast_gld'], mode='lines+markers', name='30-day Forecast'
))
forecast_fig.update_layout(title='GLD Forecast: Historical, Backtest, and 30-Business-Day Projection', height=460, margin=dict(l=20,r=20,t=50,b=20))

bench_fig = px.bar(bench_df.sort_values('rmse'), x='model', y=['rmse','mae'], barmode='group', title='Model Benchmark (Lower is Better)')
bench_fig.update_layout(height=380, margin=dict(l=20,r=20,t=50,b=20))

gld['month_name'] = gld['Date'].dt.strftime('%b')
month_order = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
seasonality = gld.groupby('month_name', as_index=False)['GLD'].mean()
seasonality['month_name'] = pd.Categorical(seasonality['month_name'], categories=month_order, ordered=True)
seasonality = seasonality.sort_values('month_name')
seasonality_fig = px.line(seasonality, x='month_name', y='GLD', markers=True, title='Seasonality Check: Average GLD by Month')
seasonality_fig.update_layout(height=350, margin=dict(l=20,r=20,t=50,b=20), xaxis_title='Month', yaxis_title='Average GLD')

bigmart_sales = bigmart.groupby('Outlet_Type', as_index=False)['Item_Outlet_Sales'].mean().sort_values('Item_Outlet_Sales')
bigmart_fig = px.bar(bigmart_sales, x='Item_Outlet_Sales', y='Outlet_Type', orientation='h', title='Supporting Insight: Average BigMart Sales by Outlet Type')
bigmart_fig.update_layout(height=350, margin=dict(l=20,r=20,t=50,b=20), yaxis_title='', xaxis_title='Average Sales')

insurance_fig = px.box(insurance, x='smoker', y='charges', color='smoker', title='Supporting Insight: Insurance Charges Distribution by Smoking Status', points='outliers')
insurance_fig.update_layout(height=350, margin=dict(l=20,r=20,t=50,b=20), xaxis_title='Smoker', yaxis_title='Charges')

top_catalog = catalog.sort_values('rows', ascending=False).copy()
table_html = top_catalog.to_html(index=False, classes='data-table', border=0)

def fig_html(fig, include_js=False):
    return fig.to_html(full_html=False, include_plotlyjs='cdn' if include_js else False, config={'displayModeBar': False})

summary_cards = f"""
<div class="cards">
  <div class="card"><div class="label">Datasets</div><div class="value">{project_summary['dataset_count']}</div><div class="sub">cataloged from uploads</div></div>
  <div class="card"><div class="label">Rows</div><div class="value">{project_summary['total_rows']:,}</div><div class="sub">across all CSV files</div></div>
  <div class="card"><div class="label">Best Forecast Model</div><div class="value">{project_summary['best_model']}</div><div class="sub">RMSE {project_summary['best_rmse']:.3f}</div></div>
  <div class="card"><div class="label">30-Day GLD Forecast</div><div class="value">{project_summary['day_30_forecast_gld']:.2f}</div><div class="sub">latest actual {project_summary['latest_actual_gld']:.2f}</div></div>
</div>
"""

html = f"""
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>Curated Forecast Dashboard</title>
<style>
body {{ font-family: Arial, Helvetica, sans-serif; margin:0; background:#f4f7fb; color:#182230; }}
.header {{ background:linear-gradient(135deg,#0f172a,#1d4ed8); color:white; padding:32px 40px; }}
.header h1 {{ margin:0 0 8px 0; font-size:34px; }}
.header p {{ margin:0; opacity:0.92; max-width:900px; line-height:1.5; }}
.container {{ padding:24px 32px 40px 32px; }}
.cards {{ display:grid; grid-template-columns:repeat(4,1fr); gap:16px; margin:20px 0 28px 0; }}
.card {{ background:white; border-radius:14px; padding:18px 20px; box-shadow:0 8px 24px rgba(15,23,42,0.08); }}
.card .label {{ font-size:13px; color:#64748b; text-transform:uppercase; letter-spacing:0.08em; }}
.card .value {{ font-size:30px; font-weight:700; margin-top:6px; }}
.card .sub {{ font-size:13px; color:#64748b; margin-top:4px; }}
.section {{ margin-top:28px; }}
.grid-2 {{ display:grid; grid-template-columns:1.25fr 1fr; gap:18px; }}
.grid-3 {{ display:grid; grid-template-columns:1fr 1fr; gap:18px; }}
.panel {{ background:white; border-radius:14px; padding:14px; box-shadow:0 8px 24px rgba(15,23,42,0.08); }}
.panel h2 {{ margin:6px 10px 2px 10px; font-size:20px; }}
.panel p {{ margin:0 10px 8px 10px; color:#475569; line-height:1.5; }}
.data-table {{ width:100%; border-collapse:collapse; font-size:13px; }}
.data-table th, .data-table td {{ padding:8px 10px; border-bottom:1px solid #e2e8f0; text-align:left; }}
.data-table th {{ background:#eff6ff; position:sticky; top:0; }}
.note {{ font-size:13px; color:#475569; background:#eff6ff; border-left:4px solid #2563eb; padding:10px 12px; border-radius:8px; margin:12px 0 0 0; }}
.footer {{ color:#64748b; font-size:12px; margin-top:18px; }}
@media (max-width: 1100px) {{
  .cards, .grid-2, .grid-3 {{ grid-template-columns:1fr; }}
}}
</style>
</head>
<body>
<div class="header">
  <h1>Curated Forecast & Portfolio Analytics Dashboard</h1>
  <p>This dashboard uses the uploaded datasets as a portfolio catalog and builds a deep-dive forecast on <b>GLD gold price data</b>, the strongest time-series candidate in the collection. Supporting panels from BigMart and Insurance show how the broader dataset set can power revenue and pricing analytics.</p>
</div>
<div class="container">
  {summary_cards}
  <div class="section grid-2">
    <div class="panel">
      <h2>Dataset portfolio overview</h2>
      <p>Each uploaded CSV was profiled for size, feature richness, missingness, and recommended analytical use case.</p>
      {fig_html(catalog_fig, include_js=True)}
    </div>
    <div class="panel">
      <h2>Catalog detail</h2>
      <p>Recommended use cases help position these files into a client-facing project roadmap.</p>
      <div style="max-height:460px; overflow:auto;">{table_html}</div>
      <div class="note"><b>Curated choice for forecasting:</b> <code>gld_price_data.csv</code> was selected because it contains a clean date index and continuous historical target values, making it appropriate for recursive forecasting.</div>
    </div>
  </div>

  <div class="section">
    <div class="panel">
      <h2>GLD forecast workspace</h2>
      <p>The forecast uses lag, rolling mean/volatility, and calendar features. Models were benchmarked chronologically, and the best performer was refit on the full history before generating a 30-business-day projection.</p>
      {fig_html(forecast_fig)}
    </div>
  </div>

  <div class="section grid-3">
    <div class="panel">
      <h2>Forecast model benchmark</h2>
      <p>Ridge regression delivered the strongest out-of-sample accuracy on the backtest.</p>
      {fig_html(bench_fig)}
    </div>
    <div class="panel">
      <h2>GLD seasonality check</h2>
      <p>Monthly averages help explain whether the target shows systematic seasonal tendencies.</p>
      {fig_html(seasonality_fig)}
    </div>
  </div>

  <div class="section grid-3">
    <div class="panel">
      <h2>Supporting business insight: BigMart</h2>
      <p>Retail sales patterns can feed a future demand-planning or outlet-performance workstream.</p>
      {fig_html(bigmart_fig)}
    </div>
    <div class="panel">
      <h2>Supporting business insight: Insurance</h2>
      <p>Pricing dispersion by smoking status shows a strong segmentation effect and a clear candidate for supervised modeling.</p>
      {fig_html(insurance_fig)}
    </div>
  </div>

  <div class="footer">
    Files generated alongside this dashboard: dataset catalog, GLD model benchmark, GLD backtest predictions, 30-business-day forecast, BigMart outlet summary, and Insurance smoking summary.
  </div>
</div>
</body>
</html>
"""

out_path = out_dir / 'curated_forecast_dashboard.html'
out_path.write_text(html, encoding='utf-8')
print(f'Wrote dashboard to {out_path}')
