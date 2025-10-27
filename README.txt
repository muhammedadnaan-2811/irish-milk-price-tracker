# 🥛 Irish Milk Price Tracker (SQL + Tableau)

### 📊 Project Summary
Built a simplified “Dairy Value Chain Pulse” using **CSO PxStat** official data to track:
- Farm-gate milk output prices (AOPI)
- Input costs (fertiliser, energy, feed)
- Retail CPI for milk, cheese & eggs

The dashboard visualises **margin spread** and **price-pass-through lag** in Ireland’s dairy sector (Base 2020 = 100).

---

### 🧰 Tools & Stack
| Stage | Tool |
|-------|------|
| Data prep | PostgreSQL (pgAdmin) |
| ETL logic | SQL (window functions, joins, KPIs) |
| Visualisation | Tableau Public |
| Source data | CSO PxStat AHM05 & CPM18 |

---

### 📂 Repository Structure
irish-milk-price-tracker/
├── data/ # Raw & cleaned CSVs
├── sql/ # SQL scripts (DDL, transformations)
├── tableau/ # .twbx dashboard
├── docs/ # Screenshots or references
└── README.md


---

### 🧮 Key KPIs
- **Input Avg Index** = mean(Fertiliser, Energy, Feed)  
- **Spread** = Output − Input Avg  
- **Correlation (Farm vs Retail)** ≈ 0.41 → moderate positive link  

---

### 📈 Dashboards
1. **Farm vs Input Costs** → Milk Output vs Input Average  
2. **Farm vs Retail CPI** → Retail price lag visualisation  

👉 *View the interactive dashboard on [Tableau Public](https://public.tableau.com/app/profile/)* (insert your link).

---

### 🗓️ Timeline
| Week | Focus |
|------|--------|
| 1 | Download CSO data & model tables |
| 2 | Create KPIs (Spread, MoM, YoY) |
| 3 | Build Tableau dashboards & publish |

---

### 🧠 Insights
- Input costs spiked before milk prices, compressing margins.  
- Retail prices lag farm-gate movements by ~3 months.  
- Suggests index-linked contracts or better promo timing.  

---

### 📜 References
- CSO PxStat AHM05 (Agricultural Input & Output Price Indices)  
- CSO PxStat CPM18 (Consumer Price Index)  
