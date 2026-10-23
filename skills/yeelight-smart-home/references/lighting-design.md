# 灯光设计

- `lighting.design.plan`：输入 scene（reading/movie/relax/work/sleep 或中文名）或自定义 plan
  {brightness, color_temperature, power...}，输出分步计划（不执行）。
- `lighting.design.apply`：执行计划；**需要 parameters.confirmed=true**（R2 带 R3 式确认，
  因为是批量多属性写）。逐设备逐属性写 + 读回验证；部分失败 partial。
- `lighting.flow.execute`：灯效/流（写 flow 属性）。
- `lighting.design.import`：not_supported（stretch：/v1/meta/import + /v1/meta/status 轮询）。
