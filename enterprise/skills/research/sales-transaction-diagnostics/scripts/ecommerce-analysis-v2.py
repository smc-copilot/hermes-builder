#!/usr/bin/env python3
"""
B2B电商/分销业务数据诊断分析脚本 (V2 - Full)
功能: 
  1. 智能解析含逗号的物料代码CSV（电子元器件行业常见）
  2. 多维度聚合分析：客户集中度、销售绩效、产品结构、毛利率、退货
  3. 输出结构化指标供Word报告生成

用法:
  1. 将原始CSV保存到 RAW_DATA_PATH
  2. 修改 FILE_COLUMNS 与数据匹配（见下方注释）
  3. python3 ecommerce-analysis-v2.py

数据格式假设:
  列: 销售部门,销售员,客户代码,客户名称,付款条款,物料代码,数量,销售额,采购员,归属毛利,业务类型
  - 物料代码(第6列)可能含逗号: "74HC00D,653", "LM2596SX-ADJ/NOPB"
  - 数量、销售额、归属毛利为数字，可能含有千分位逗号
  - 负数销售额 = 退货/冲销
"""

import csv
from collections import defaultdict

# ============================================================
# 配置
# ============================================================
RAW_DATA_PATH = "/data/hermes/workspace/materials/ecommerce_2023_raw_data.csv"

# 列定义（0-indexed）
COL_DEPT = 0        # 销售部门修正
COL_SALES = 1       # 销售员重置
COL_CUST_CODE = 2   # 客户代码
COL_CUST_NAME = 3   # 客户名称
COL_PAYMENT = 4     # 付款条款
COL_MATERIAL = 5    # 物料代码（可能含逗号）
COL_QTY = 6         # 数量
COL_AMOUNT = 7      # 修正后实际销售额
COL_PURCHASER = 8   # 采购员
COL_GROSS = 9       # 归属毛利
COL_BIZ_TYPE = 10   # 业务类型

EXPECTED_FIELDS = 11  # 标准行应有的字段数

# ============================================================
# 数据加载：智能解析CSV（处理物料代码中的逗号）
# ============================================================

def parse_csv_line(line):
    parts = line.split(',')
    
    if len(parts) == EXPECTED_FIELDS:
        return parts
    elif len(parts) > EXPECTED_FIELDS:
        # 物料代码中含有逗号 → 从右向左装配
        biz_type = parts[-1].strip()
        gross_profit = parts[-2].strip()
        purchaser = parts[-3].strip()
        amount = parts[-4].strip()
        qty = parts[-5].strip()
        material_code = ','.join(parts[COL_MATERIAL:-5]).strip()
        
        result = parts[:COL_MATERIAL] + [material_code, qty, amount, purchaser, gross_profit, biz_type]
        return result
    else:
        return None  # 无法解析

def clean_num(val):
    """清理数字字段：去掉千分位逗号和空格"""
    if val is None or str(val).strip() in ('', '-', 'N/A'):
        return 0.0
    try:
        return float(str(val).replace(',', '').replace(' ', '').strip())
    except ValueError:
        return 0.0

def load_data(filepath):
    records = []
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    for i, line in enumerate(lines[1:], 2):  # skip header
        line = line.strip()
        if not line:
            continue
        
        parts = parse_csv_line(line)
        if parts is None:
            print(f"WARN: 第{i}行无法解析，跳过: {line[:60]}...")
            continue
        
        record = {
            'dept': parts[COL_DEPT].strip(),
            'salesperson': parts[COL_SALES].strip(),
            'cust_code': parts[COL_CUST_CODE].strip(),
            'cust_name': parts[COL_CUST_NAME].strip(),
            'payment': parts[COL_PAYMENT].strip(),
            'material': parts[COL_MATERIAL].strip(),
            'qty': clean_num(parts[COL_QTY]),
            'amount': clean_num(parts[COL_AMOUNT]),
            'purchaser': parts[COL_PURCHASER].strip(),
            'gross': clean_num(parts[COL_GROSS]),
            'biz_type': parts[COL_BIZ_TYPE].strip(),
        }
        records.append(record)
    
    return records

def classify_record(r):
    """按金额正负和数值分类"""
    if r['amount'] > 0 and r['gross'] >= 0:
        return 'revenue'
    elif r['amount'] > 0 and r['gross'] < 0:
        return 'revenue_with_loss'
    elif r['amount'] < 0:
        return 'return'
    elif r['amount'] == 0:
        return 'zero'
    return 'other'

# ============================================================
# 分析函数
# ============================================================

def analyze_customers(records):
    """客户维度分析：销售额、毛利、交易次数、物料多样性"""
    data = defaultdict(lambda: {'sales': 0, 'gross': 0, 'count': 0, 'materials': set()})
    for r in records:
        key = (r['cust_code'], r['cust_name'])
        if not key[0]:
            continue
        data[key]['sales'] += r['amount']
        data[key]['gross'] += r['gross']
        data[key]['count'] += 1
        if r['material']:
            data[key]['materials'].add(r['material'])
    
    sorted_data = sorted(data.items(), key=lambda x: -x[1]['sales'])
    total_sales = sum(d['sales'] for _, d in sorted_data) or 1
    
    print(f"  客户总数: {len(sorted_data)}")
    print(f"\n  Top 10 客户:")
    print(f"  {'客户名称':28s} {'销售额':>12s} {'毛利':>10s} {'次数':>4s} {'SKU':>4s} {'占比':>6s}")
    print(f"  {'-'*28} {'-'*12} {'-'*10} {'-'*4} {'-'*4} {'-'*6}")
    cum = 0
    for i, ((code, name), d) in enumerate(sorted_data[:10]):
        pct = d['sales'] / total_sales * 100
        cum += pct
        print(f"  {i+1:2d}.{name[:24]:24s} ${d['sales']:>9,.2f} ${d['gross']:>7,.2f} {d['count']:4d} {len(d['materials']):4d} {pct:>5.1f}%")
    
    print(f"\n  客户集中度:")
    top1 = sorted_data[0][1]['sales'] / total_sales * 100
    top3 = sum(d['sales'] for _, d in sorted_data[:3]) / total_sales * 100
    top5 = sum(d['sales'] for _, d in sorted_data[:5]) / total_sales * 100
    print(f"    Top1={top1:.1f}%, Top3={top3:.1f}%, Top5={top5:.1f}%")
    
    # 客户质量分级
    grades = {'A': [], 'B': [], 'C': [], 'D': []}
    for (code, name), d in sorted_data:
        margin = d['gross'] / d['sales'] * 100 if d['sales'] > 100 else 0
        if margin >= 15 and d['count'] >= 3:
            grades['A'].append((name, d['sales'], margin))
        elif 10 <= margin < 15 and d['count'] >= 2:
            grades['B'].append((name, d['sales'], margin))
        elif margin < 10 and d['count'] >= 3:
            grades['C'].append((name, d['sales'], margin))
        else:
            grades['D'].append((name, d['sales'], margin))
    
    print(f"\n  客户质量分级:")
    for grade in ['A', 'B', 'C', 'D']:
        names = ', '.join(f"{n}({s:.0f})" for n, s, m in grades[grade][:5])
        print(f"    {grade}级({len(grades[grade])}个): {names}")
    
    return sorted_data

def analyze_salespersons(records):
    """销售员维度分析"""
    data = defaultdict(lambda: {'sales': 0, 'gross': 0, 'count': 0, 'customers': set()})
    for r in records:
        s = r['salesperson'] or '(空)'
        data[s]['sales'] += r['amount']
        data[s]['gross'] += r['gross']
        data[s]['count'] += 1
        data[s]['customers'].add(r['cust_code'])
    
    sorted_data = sorted(data.items(), key=lambda x: -x[1]['sales'])
    
    print(f"\n  销售员业绩:")
    print(f"  {'销售员':8s} {'销售额':>12s} {'毛利':>10s} {'次数':>4s} {'客户数':>4s} {'毛利率':>6s}")
    print(f"  {'-'*8} {'-'*12} {'-'*10} {'-'*4} {'-'*4} {'-'*6}")
    for s, d in sorted_data:
        margin = d['gross'] / d['sales'] * 100 if d['sales'] else 0
        print(f"  {s:8s} ${d['sales']:>9,.2f} ${d['gross']:>7,.2f} {d['count']:4d} {len(d['customers']):4d} {margin:>5.1f}%")
    
    return sorted_data

def analyze_materials(records):
    """物料维度分析"""
    data = defaultdict(lambda: {'sales': 0, 'gross': 0, 'qty': 0, 'count': 0, 'customers': set()})
    for r in records:
        mat = r['material'] or '(空)'
        data[mat]['sales'] += r['amount']
        data[mat]['gross'] += r['gross']
        data[mat]['qty'] += r['qty']
        data[mat]['count'] += 1
        data[mat]['customers'].add(r['cust_code'])
    
    sorted_data = sorted(data.items(), key=lambda x: -x[1]['sales'])
    total = sum(d['sales'] for _, d in sorted_data) or 1
    
    print(f"\n  总SKU数: {len(sorted_data)}")
    top5 = sum(d['sales'] for _, d in sorted_data[:5]) / total * 100
    top10 = sum(d['sales'] for _, d in sorted_data[:10]) / total * 100
    print(f"  SKU集中度: Top5={top5:.1f}%, Top10={top10:.1f}%")
    
    print(f"  Top 10 SKU:")
    print(f"  {'物料代码':28s} {'销售额':>10s} {'毛利':>9s} {'毛利率':>5s} {'数量':>8s}")
    for mat, d in sorted_data[:10]:
        m = d['gross'] / d['sales'] * 100 if d['sales'] else 0
        print(f"  {mat[:26]:26s} ${d['sales']:>7,.2f} ${d['gross']:>6,.2f} {m:>4.1f}% {d['qty']:>7,.0f}")
    
    return sorted_data

def analyze_biz_types(records):
    """业务类型分析"""
    data = defaultdict(lambda: {'sales': 0, 'gross': 0, 'count': 0, 'customers': set()})
    for r in records:
        bt = r['biz_type'] or '(空)'
        data[bt]['sales'] += r['amount']
        data[bt]['gross'] += r['gross']
        data[bt]['count'] += 1
        data[bt]['customers'].add(r['cust_code'])
    
    for bt, d in sorted(data.items(), key=lambda x: -x[1]['sales']):
        m = d['gross'] / d['sales'] * 100 if d['sales'] else 0
        print(f"  {bt:35s} ${d['sales']:>9,.2f} ${d['gross']:>7,.2f} {m:>5.1f}% 客户={len(d['customers'])}")

def analyze_purchasers(records):
    """采购员分析"""
    data = defaultdict(lambda: {'sales': 0, 'gross': 0, 'count': 0, 'materials': set()})
    for r in records:
        p = r['purchaser'] or '(空)'
        data[p]['sales'] += r['amount']
        data[p]['gross'] += r['gross']
        data[p]['count'] += 1
        data[p]['materials'].add(r['material'])
    
    sorted_data = sorted(data.items(), key=lambda x: -x[1]['sales'])
    print(f"\n  采购员业绩:")
    print(f"  {'采购员':8s} {'采购额':>12s} {'毛利':>9s} {'次数':>4s} {'SKU':>4s} {'毛利率':>5s}")
    for p, d in sorted_data:
        if d['sales'] > 100:
            m = d['gross'] / d['sales'] * 100 if d['sales'] else 0
            print(f"  {p:8s} ${d['sales']:>9,.2f} ${d['gross']:>6,.2f} {d['count']:4d} {len(d['materials']):4d} {m:>4.1f}%")

def main():
    print("=" * 60)
    print("  电商/分销业务数据诊断分析 (V2 Full)")
    print("=" * 60)
    
    # 加载数据
    print(f"\n[1] 加载数据: {RAW_DATA_PATH}")
    all_records = load_data(RAW_DATA_PATH)
    print(f"    共加载 {len(all_records)} 条记录")
    
    total_sales = sum(r['amount'] for r in all_records)
    total_gross = sum(r['gross'] for r in all_records)
    print(f"    总销售额: ${total_sales:,.2f}")
    print(f"    总归属毛利: ${total_gross:,.2f}")
    
    # 按部门拆分
    print(f"\n[2] 按销售部门汇总:")
    dept_data = defaultdict(lambda: {'sales': 0, 'gross': 0, 'count': 0})
    for r in all_records:
        dept = r['dept'] or '(空)'
        dept_data[dept]['sales'] += r['amount']
        dept_data[dept]['gross'] += r['gross']
        dept_data[dept]['count'] += 1
    for dept, d in sorted(dept_data.items(), key=lambda x: -x[1]['sales']):
        print(f"  {dept:20s}: 销售额=${d['sales']:>10,.2f}, 毛利=${d['gross']:>8,.2f}, 记录数={d['count']}")
    
    # 电商中心深度分析
    print(f"\n[3] 电商中心核心指标:")
    ec_records = [r for r in all_records if r['dept'] == '电商中心']
    ec_positive = [r for r in ec_records if r['amount'] > 0]
    ec_negative = [r for r in ec_records if r['amount'] < 0]
    
    ec_sales = sum(r['amount'] for r in ec_records)
    ec_gross = sum(r['gross'] for r in ec_records)
    ec_pos_sales = sum(r['amount'] for r in ec_positive)
    ec_pos_gross = sum(r['gross'] for r in ec_positive)
    neg_amount = sum(r['amount'] for r in ec_negative)
    neg_gross = sum(r['gross'] for r in ec_negative)
    
    print(f"  总记录: {len(ec_records)} (正向={len(ec_positive)}, 退货={len(ec_negative)})")
    print(f"  净销售额: ${ec_sales:>8,.2f}  净毛利: ${ec_gross:>8,.2f}  毛利率: {ec_gross/ec_sales*100:.1f}%" if ec_sales else "")
    print(f"  正向销售额: ${ec_pos_sales:>8,.2f}  正向毛利: ${ec_pos_gross:>8,.2f}  毛利率: {ec_pos_gross/ec_pos_sales*100:.1f}%")
    print(f"  退货金额: ${neg_amount:>9,.2f}  退货毛利损失: ${neg_gross:>8,.2f}")
    
    # 客户分析
    print(f"\n[4] 客户维度分析:")
    top_customers = analyze_customers(ec_positive)
    
    # 销售分析
    print(f"\n[5] 销售员维度分析:")
    top_sales = analyze_salespersons(ec_positive)
    
    # 物料分析
    print(f"\n[6] 物料维度分析:")
    top_materials = analyze_materials(ec_positive)
    
    # 业务类型分析
    print(f"\n[7] 业务类型分析:")
    analyze_biz_types(ec_positive)
    
    # 采购分析
    print(f"\n[8] 采购员维度分析:")
    analyze_purchasers(ec_positive)
    
    # 综合诊断
    print(f"\n[9] 综合诊断:")
    unit_cost = 450000  # $450K team cost
    total_gross_all = sum(r['gross'] for r in all_records)
    print(f"  团队年成本: ${unit_cost:,}")
    print(f"  总毛利(含日本): ${total_gross_all:,.2f}")
    print(f"  毛利覆盖率: {total_gross_all/unit_cost*100:.1f}%")
    print(f"  毛利缺口: ${unit_cost - total_gross_all:,.2f}")
    
    # 关键发现摘要
    print(f"\n[10] 关键发现摘要:")
    if top_customers:
        top1 = top_customers[0]
        print(f"  最大客户: {top1[0][1]}, 占比={top1[1]['sales']/sum(d['sales'] for _,d in top_customers)*100:.1f}%")
    if top_sales:
        print(f"  最佳销售: {top_sales[0][0]}, 销售额=${top_sales[0][1]['sales']:,.2f}")
    
    single_buy = sum(1 for _, d in top_customers if d['count'] == 1)
    multi_buy = sum(1 for _, d in top_customers if d['count'] > 1)
    total_cust = len(top_customers)
    print(f"  总客户数: {total_cust}, 单次交易: {single_buy}({single_buy/total_cust*100:.0f}%), 复购: {multi_buy}({multi_buy/total_cust*100:.0f}%)")
    
    print(f"\n{'='*60}")
    print(f"  分析完成")
    print(f"{'='*60}")

if __name__ == '__main__':
    main()
