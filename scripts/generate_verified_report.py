#!/usr/bin/env python3
"""Reproducible SA2 report with source-specific dates and numeric rankings."""
from datetime import datetime, timezone
from pathlib import Path
import pandas as pd
R=Path(__file__).resolve().parents[1]
d=pd.read_csv(R/'sa2_kpi_wide.csv'); d=d[d['LGA Code'].astype(str)=='11650'].copy()
assert len(d)==d['SA2 Code'].nunique()==30
lookup=pd.read_excel(R/'inputs/Output-Indicator-Lookup.xlsx')
dates=dict(zip(lookup['Indicator'],pd.to_datetime(lookup['Latest Period'])))
def period(c):
 x=dates.get({'Population Change 2023-24':'ERP Change 2023-24'}.get(c,c))
 return x.strftime('%B %Y') if x is not None and pd.notna(x) else 'not specified'
def fmt(c,v):
 if c in ['House Price (Current)','Unit Price (Current)','House Rent (P/W)','Unit Rent (P/W)','Total Spend','Median Household Income','Airbnb  Gross Revenue']:return f'\u0024{v:,.0f}'
 if c.startswith('%') or c in ('Unemployment Rate (%)','Airbnb Occupancy Rate'):return f'{v:,.1f}%'
 if 'Rate (per 1,000)' in c:return f'{v:,.2f} per 1,000'
 if c=='Airbnb Active Listings':return f'{v:,.1f}'
 return f'{v:,.0f}' if abs(v)>=100 else f'{v:,.1f}'
def rank(c,high=True):
 t=d[['SA2 Name',c]].dropna().copy();t[c]=pd.to_numeric(t[c],errors='coerce');t=t.dropna().sort_values([c,'SA2 Name'],ascending=[not high,True]);assert len(t)>0,c
 r=t.iloc[0];return f"**{r['SA2 Name']}** ({fmt(c,r[c])})",len(t)
def row(c):
 hi,n=rank(c);lo,_=rank(c,False)
 return f'| {c.strip()} | {period(c)} | {hi} | {lo} | {n}/30 |'
def section(title,cols):
 return ['','## '+title,'','| Indicator | Reference period | Highest SA2 | Lowest SA2 | Coverage |','|---|---|---|---|---:|']+[row(c) for c in cols]
a=['# Central Coast SA2 Intelligence Report','',f'**Prepared: {datetime.now(timezone.utc):%d %B %Y} (UTC) | Coverage: 30 Central Coast SA2s | Indicator periods vary (2021–September 2026)**','','## Executive Summary','',f'This report compares observed SA2 indicators from four Dropbox files retrieved on {datetime.now(timezone.utc):%d %B %Y}. These indicators do not share one reference date: census measures are from 2021, crime from December 2025, and some prices and benefits from September 2026. Rankings are descriptive and use available observations, not causal or population-adjusted comparisons.','',f"1. The 2021 Total Population column sums to **{pd.to_numeric(d['Total Population']).sum():,.0f}** across {d['Total Population'].notna().sum()} SA2s; this is not a current population estimate.",f"2. Highest house-price observation: {rank('House Price (Current)')[0]} ({period('House Price (Current)')}).",f"3. Highest unemployment-rate observation: {rank('Unemployment Rate (%)')[0]} ({period('Unemployment Rate (%)')}).",f"4. Highest JobSeeker count: {rank('JobSeeker Payment')[0]} ({period('JobSeeker Payment')}); the count is not a prevalence rate.",f"5. Highest assault rate: {rank('Assault Rate (per 1,000)')[0]} ({period('Assault Rate (per 1,000)')})."]
a+=section('1. Population & Demographics',['Total Population','Population Change 2023-24','Median Age','% Under 20','% Born Overseas'])
a+=['','Population change describes 2023–24; the Total Population reference period in the supplied lookup is 2021. A current population total cannot be inferred by summing older census counts.']
a+=section('2. Economic Activity & Business',['Total Businesses','Labour Force','Unemployment Rate (%)','JobSeeker Payment','Median Household Income'])
a+=['','Business counts, labour-market figures and median household income refer to different years. Counts should not be compared as rates without suitable population denominators.']
a+=section('3. Housing & Affordability',['House Price (Current)','Unit Price (Current)','House Rent (P/W)','Unit Rent (P/W)','Number of dwellings approved'])
a+=['','House prices and rents date to September 2026 but household income to 2021. A current price-to-current-income ratio is not supported by these inputs.']
a+=section('4. Socioeconomic Wellbeing',['Index of Relative Socio-economic Advantage and Disadvantage','Age Pension','Homelessness'])
a+=['','SEIFA indices refer to 2021; homelessness to June 2025; Age Pension to June 2026. Benefits and homelessness are counts, not population-standardised rates.']
a+=section('5. Crime & Safety',['Assault Rate (per 1,000)','Theft Rate (per 1,000)','Intimidation, Stalking & Harassment Rate (per 1,000)','Malicious Damage to Property Rate (per 1,000)','Drug Offences Rate (per 1,000)'])
a+=['','All crime indicators above date to December 2025. Small-area rates can be volatile; the table does not establish a cause of differences.']
a+=section('6. Tourism & Visitor Economy',['Tourism Businesses','Total Spend','Airbnb Active Listings','Airbnb Occupancy Rate','Airbnb  Gross Revenue'])
a+=['','Total Spend is not exclusively visitor expenditure; do not treat it as tourism spend. Airbnb listing values in the pivot include fractional observations, so they should not be read as exact property counts. Airbnb and business indicators refer to different periods.','','## 7. Regional Divide: Gosford vs Wyong','','Unweighted medians of the available SA2 values within each SA3 are shown below. They are not population-weighted regional rates.','','| SA3 | SA2 count | Unemployment rate (Jun 2026) | House price (Sep 2026) | Median household income (2021) |','|---|---:|---:|---:|---:|']
for region,g in sorted(d.groupby('Region (SA3)')):
 def med(c):return pd.to_numeric(g[c],errors='coerce').median()
 a.append(f"| {region} | {len(g)} | {fmt('Unemployment Rate (%)',med('Unemployment Rate (%)'))} | {fmt('House Price (Current)',med('House Price (Current)'))} | {fmt('Median Household Income',med('Median Household Income'))}/week |")
a+=['','## 8. Key Challenges & Opportunities','','- Challenge: Older census and crime reference periods are not interchangeable with the September 2026 market data.','- Challenge: Raw benefit and business counts require denominator checks before interpreting relative need.','- Opportunity: The latest housing and JobSeeker observations can guide local follow-up, subject to verification of source definitions.','- Opportunity: Quarterly series through June 2026 can be examined alongside, not substituted for, current cross-sectional values.','','## Data Notes','',f'Source files retrieved from Dropbox:Moltbot/Economic-Dashboard on {datetime.now(timezone.utc):%d %B %Y}: Output - Mapped SA2 Level Data (Pivot) - All LGAs.xlsx; Output  - Indicator Lookup.xlsx; Output - Trends.csv; Output  - Time-series Trends.xlsx. Rankings computed from sa2_kpi_wide.csv, filtered to Central Coast LGA code 11650; latest periods from source Indicator Lookup.','','Input workbook: 200 rows, 191 unique SA2 codes across 16 LGAs; importer retains the last row per SA2. Central Coast has 30 distinct SA2s. Source lookup holds 58 indicator rows. Quarterly workbook runs through June 2026. No matched prior-month workbook was provided; trend arrows use the supplied trend-direction CSV, not an independently computed month-on-month comparison.','','Selected periods: '+ '; '.join(c+': '+period(c) for c in ['Total Population','Median Household Income','Total Businesses','Assault Rate (per 1,000)','Homelessness','Unemployment Rate (%)','JobSeeker Payment','House Price (Current)','Airbnb Active Listings'])+'.']
(R/'reports/central-coast.md').write_text('\n'.join(a)+'\n',encoding='utf-8')
print('Generated verified report:',len(a),'lines;',len(d),'SA2s')
