# 物模型字段

Property（属性）：
- propId：p/l/c/ct/tp 等；operators：set/toggle/adjust；valueRange/valueList 枚举。
- scale/zoom：数值缩放。

Device：
- subDeviceList：多键面板/多子设备，index 从 1 开始，每个子设备独立控制。
- nodeType：2 设备；roomId 归属；category 品类。

Node 控制节点类型：1 房间、2 设备、3 自定义组、4 Mesh 灯组、5 家庭、6 情景、12 自动化。

事件（events）：name/id/desc；传感器事件写入走 sensor.event.write。
