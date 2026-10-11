#!/bin/bash
# Checks RAD's Ximmio calendar for one address: is the address known, which
# fields and waste types come back, and the dates for the next 60 days.
#   ./scripts/probe-ximmio.sh 3241XB 45
# Needs curl and jq. Prints no address details beyond the community.
set -euo pipefail

PC="${1:?postcode}"; NR="${2:?huisnummer}"
BASE=https://wasteprod2api.ximmio.com
CODE=13a2cad9-36d0-4b01-b877-efcb421a864d   # RAD BV, as in ClikoCore/Ximmio.swift

addr=$(curl -fsS -m 20 -X POST "$BASE/api/FetchAdress" \
    --data-urlencode "postCode=$PC" --data-urlencode "houseNumber=$NR" --data-urlencode "companyCode=$CODE")
id=$(jq -r '.dataList[0].UniqueId // empty' <<<"$addr")
community=$(jq -r '.dataList[0].Community // ""' <<<"$addr")
if [ -z "$id" ]; then
X
    exit 1
fi
echo "✓ adres gevonden (community: ${community:--}); velden: $(jq -c '.dataList[0] | keys' <<<"$addr")"

start=$(date +%F)
end=$(date -d '+60 days' +%F 2>/dev/null || date -v+60d +%F)
cal=$(curl -fsS -m 20 -X POST "$BASE/api/GetCalendar" \
    --data-urlencode "uniqueAddressID=$id" --data-urlencode "startDate=$start" --data-urlencode "endDate=$end" \
    --data-urlencode "companyCode=$CODE" --data-urlencode "community=$community")
echo "velden per afvalsoort: $(jq -c '[.dataList[]? | keys] | add | unique' <<<"$cal")"
jq -r '.dataList[]? | "\(._pickupTypeText)\t\(.description)\t\(.pickupDates | map(.[0:10]) | join(" "))"' <<<"$cal"
echo "✓ $(jq '[.dataList[]?.pickupDates | length] | add // 0' <<<"$cal") ophaalmomenten"
