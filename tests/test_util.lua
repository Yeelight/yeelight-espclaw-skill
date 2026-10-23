-- tests/test_util.lua
local mock = require("tests.mock")
local util = require("util")

mock.assert_eq(util.trim("  hello  "), "hello", "trim")
mock.assert_eq(util.clamp(120, 1, 100), 100, "clamp high")
mock.assert_eq(util.clamp(-5, 1, 100), 1, "clamp low")
mock.assert_eq(util.to_int("42"), 42, "to_int")
mock.assert_eq(util.to_int("abc"), nil, "to_int invalid")
mock.assert(util.is_array({ 1, 2, 3 }), "is_array")
mock.assert(not util.is_array({ a = 1 }), "is_array object")

local escaped = util.url_escape("a b/c+d")
mock.assert_eq(escaped, "a%20b%2Fc%2Bd", "url_escape")

-- base64url / JWT
local payload = '{"exp":4102444800}'
local encoded = mock.base64url(payload)
local decoded = util.base64url_decode(encoded)
mock.assert_eq(decoded, payload, "base64url roundtrip")
mock.assert_eq(util.jwt_exp("header." .. encoded .. ".sig"), 4102444800, "jwt_exp")
mock.assert_eq(util.jwt_exp("Bearer header." .. encoded .. ".sig"), 4102444800, "jwt_exp bearer")
mock.assert_eq(util.jwt_exp("garbage"), nil, "jwt_exp garbage")

-- merge / deep_copy
local m = util.merge({ a = 1, sub = { x = 1 } }, { b = 2, sub = { y = 2 } })
mock.assert_eq(m.a, 1, "merge base")
mock.assert_eq(m.b, 2, "merge extra")
mock.assert_eq(m.sub.x, 1, "merge nested keep")
mock.assert_eq(m.sub.y, 2, "merge nested add")

-- redact
mock.assert_eq(util.redact("Authorization: Bearer abc.def.ghi"), "Authorization: Bearer ***", "redact bearer")
mock.assert(util.redact('"authorization":"tok-123"'):find("%*%*%*") ~= nil, "redact json token")

-- slice
local sl = util.slice({ 1, 2, 3, 4, 5 }, 2, 4)
mock.assert_eq(#sl, 3, "slice length")
mock.assert_eq(sl[1], 2, "slice start")
