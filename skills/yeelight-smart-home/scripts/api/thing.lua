-- api/thing.lua：物模型/产品/FAQ 域（thing.*、product.pedia.search）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")
local auth = require("auth")

local M = {}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

local function list_response(req, data, limit)
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok",
        { total = #rows, items = common.top_n(rows, limit or common.TOP_N).items })
end

M.routes = {}

M.routes["thing.schema.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/thing/schema/r/list", body = {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.schema.detail.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/thing/schema/r/list/detail", body = {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.schema.get"] = function(ctx)
    local req = ctx.req
    local product_id = contract.param(req, "productId") or contract.param(req, "pid")
    if not product_id then return missing(req, "productId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/thing/schema/r/" .. util.url_escape(tostring(product_id)), body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { schema = data.data or data })
end

M.routes["thing.schema.event.list"] = function(ctx)
    local req = ctx.req
    local product_id = contract.param(req, "productId") or contract.param(req, "pid")
    if not product_id then return missing(req, "productId") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/thing/schema/r/getEvents/" .. util.url_escape(tostring(product_id)), body = {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

local function batch_pids(req)
    local pids = contract.param(req, "pids") or contract.param(req, "productIds")
    if type(pids) ~= "table" or #pids == 0 then return nil end
    local out = {}
    for _, p in ipairs(pids) do out[#out + 1] = tostring(p) end
    return table.concat(out, ",")
end

M.routes["thing.product.info.batch_get"] = function(ctx)
    local req = ctx.req
    local pids = batch_pids(req)
    if not pids then return missing(req, "pids") end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v2/thing/schema/product/r/info?pids=" .. util.url_escape(pids),
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product.info.v3.batch_get"] = function(ctx)
    local req = ctx.req
    local pids = batch_pids(req)
    if not pids then return missing(req, "pids") end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v3/thing/schema/product/r/info?pids=" .. util.url_escape(pids),
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product.list.v3"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v3/thing/schema/product/r/list",
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product_domain.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/product-domain/r/list", body = {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.category.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v2/thing/schema/category/r/list", body = {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.component.list"] = function(ctx)
    local req = ctx.req
    local product_id = contract.param(req, "productId")
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v2/thing/schema/component/r/list",
        body = product_id and { productId = tostring(product_id) } or {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.component.get"] = function(ctx)
    local req = ctx.req
    local component_id = contract.param(req, "componentId")
    if not component_id then return missing(req, "componentId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v2/thing/schema/component/r/" .. util.url_escape(tostring(component_id)), body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { component = data.data or data })
end

M.routes["thing.property.list"] = function(ctx)
    local req = ctx.req
    local product_id = contract.param(req, "productId")
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v2/thing/schema/property/r/list",
        body = product_id and { productId = tostring(product_id) } or {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

-- 产品 FAQ
M.routes["thing.product_faq.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/platform/thing/product_faq/r/list", body = {},
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product_faq.detail.get"] = function(ctx)
    local req = ctx.req
    local faq_id = contract.param(req, "faqId") or contract.param(req, "id")
    if not faq_id then return missing(req, "faqId") end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v1/platform/thing/product_faq/r/" .. util.url_escape(tostring(faq_id)) .. "/detail",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { faq = data.data or data })
end

M.routes["thing.product_faq.type.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/platform/thing/product_faq/r/faq-types",
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product_faq.item_type.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/platform/thing/product_faq/r/faq-item-types",
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product_faq.locale.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/platform/thing/product_faq/r/locales",
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product_faq.page.list"] = function(ctx)
    local req = ctx.req
    local body = { page = contract.param(req, "pageNo") or 1 }
    local page_size = contract.param(req, "pageSize")
    if page_size then body.pageSize = page_size end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/platform/thing/product_faq/r/page", body = body,
    })
    if not data then return resp2 end
    return list_response(req, data)
end

M.routes["thing.product_faq.page_detail.list"] = function(ctx)
    local req = ctx.req
    local body = { page = contract.param(req, "pageNo") or 1 }
    local page_size = contract.param(req, "pageSize")
    if page_size then body.pageSize = page_size end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/platform/thing/product_faq/r/pageDetail", body = body,
    })
    if not data then return resp2 end
    return list_response(req, data)
end

-- 产品百科（pedia 基址）
M.routes["product.pedia.search"] = function(ctx)
    local req = ctx.req
    local keyword = contract.param(req, "keyword")
    if not keyword then return missing(req, "keyword") end
    local limit = util.clamp(contract.param(req, "limit") or 10, 1, 50)
    local data, resp2 = common.call(req, {
        method = "POST", base = auth.pedia_base(),
        path = "/v1/pedia/product/r/search",
        body = { multiField = tostring(keyword) },
    })
    if not data then return resp2 end
    return list_response(req, data, limit)
end

return M
