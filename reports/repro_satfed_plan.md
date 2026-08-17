# 复现计划: satfed

> 更新时间: 2026-08-16

## 论文
SatFed: A Resource-Efficient LEO-Satellite-Assisted Heterogeneous Federated Learning Framework (Engineering 2025, arXiv:2409.13503)

## 目标算法
SatFed（卫星辅助异构联邦学习）

## 数据集 / 模型
Fashion-MNIST / CIFAR-100（Dirichlet non-IID） / ResNet-50 (CIFAR-100) · ResNet-18 (Fashion-MNIST)

## 超参数
- devices: 20
- model: ResNet-50/ResNet-18
- optimizer: Adam
- downlink_mbps: 100
- uplink_mbps: 10
- contact_min: 10
- orbit_period_min: 100

## 期望指标（论文报告值）
- cifar100_iid_acc_gain: 0.0235
- cifar100_noniid_acc_gain: 0.0226
- fmnist_iid_acc_gain: 0.0107
- fmnist_noniid_acc_gain: 0.0101

## 复现检查清单
- [ ] 1. 数据集加载与预处理对齐（Dirichlet non-IID 划分）
- [ ] 2. 模型结构对齐（ResNet-50/18）
- [ ] 3. 算法核心逻辑实现（对照论文伪代码 Algorithm 1）
- [ ] 4. 超参数对齐（含随机种子）
- [ ] 5. 首次运行：确认能跑通
- [ ] 6. 指标对比：运行 repro_log 记录差异，迭代逼近
- [ ] 7. 收敛到论文指标（或记录并分析差异原因）

## 备注
对标项目已有 FedBuff(集中式异步)与 FedLEO(星间去中心化)；SatFed 为二者融合范本。
核心三组件：①新鲜度优先级队列 ②三类边多重图（相似性/连接/计算）③对等引导模型。
翻译文档见 文献/[24]_SatFed2025_卫星辅助异构联邦学习_中文翻译.md

## 迭代记录
见 repro_satfed_log.md（用 repro_log 工具追加）
