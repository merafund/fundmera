# задайте RPC‑endpoint; можете оставить polygon-rpc.com,
# но debug_… там обычно отключён
export ETH_RPC_URL=

TX=0x93c727766b692d645f01f3ee64e5d0a01098e003ef0fb4a1428f32ea0776b8eb
# cast run --quick $TX --rpc-url $ETH_RPC_URL --silent \
#   | grep -Eo 'Raw error: 0x[0-9a-f]+'

cast tx $TX --rpc-url $ETH_RPC_URL  -vvvvv
# дергаем RPC прямо из cast
# RAW=$(cast rpc debug_traceTransaction $TX '{"tracer":"callTracer"}' \
#       | jq -r '.error.data // .returnValue')

# echo "RAW BYTES: $RAW"