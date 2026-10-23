# 产品知识

- 物模型：`thing.schema.list/detail.list/get/event.list`（POST /v1/thing/schema/...）。
- 产品定义：`thing.product.info.batch_get`（pids=，逗号分隔，v2/v3）；
  `thing.product.list.v3`；`thing.product_domain.list`；`thing.category.list`。
- 组件/属性：`thing.component.list/get`、`thing.property.list`。
- 产品百科：`product.pedia.search`（Pedia 基址，limit 1–50 默认 10）。
- FAQ：`thing.product_faq.list/detail.get/type.list/locale.list/page.list/page_detail.list`。
- 全部为只读；大列表 top N + total。
