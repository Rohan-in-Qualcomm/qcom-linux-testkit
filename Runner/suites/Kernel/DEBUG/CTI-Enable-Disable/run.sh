#!/bin/sh

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_ENV=""
SEARCH="$SCRIPT_DIR"
while [ "$SEARCH" != "/" ]; do
    if [ -f "$SEARCH/init_env" ]; then
        INIT_ENV="$SEARCH/init_env"
        break
    fi
    SEARCH=$(dirname "$SEARCH")
done

if [ -z "$INIT_ENV" ]; then
    echo "[ERROR] Could not find init_env" >&2
    exit 1
fi

if [ -z "$__INIT_ENV_LOADED" ]; then
    # shellcheck disable=SC1090
    . "$INIT_ENV"
fi

# shellcheck disable=SC1090,SC1091
. "$TOOLS/functestlib.sh"

TESTNAME="CTI-Enable-Disable"
if command -v find_test_case_by_name >/dev/null 2>&1; then
    test_path=$(find_test_case_by_name "$TESTNAME")
    cd "$test_path" || exit 1
else
    cd "$SCRIPT_DIR" || exit 1
fi

res_file="./$TESTNAME.res"
log_info "-----------------------------------------------------------------------------------------"
log_info "-------------------Starting $TESTNAME Testcase----------------------------"
cs_base="/sys/bus/coresight/devices"
fail_count=0

etf0_sink=""
etr0_sink=""
stm0_sink=""

save_and_reset_devices() {
    log_info "Saving state and resetting Coresight devices..."
    if [ -f "$cs_base/tmc_etf0/enable_sink" ]; then
        etf0_sink=$(cat "$cs_base/tmc_etf0/enable_sink" 2>/dev/null)
        echo 0 > "$cs_base/tmc_etf0/enable_sink" 2>/dev/null || true
    fi
    if [ -f "$cs_base/tmc_etr0/enable_sink" ]; then
        etr0_sink=$(cat "$cs_base/tmc_etr0/enable_sink" 2>/dev/null)
        echo 0 > "$cs_base/tmc_etr0/enable_sink" 2>/dev/null || true
    fi
    if [ -f "$cs_base/stm0/enable_source" ]; then
        stm0_sink=$(cat "$cs_base/stm0/enable_source" 2>/dev/null)
        echo 0 > "$cs_base/stm0/enable_source" 2>/dev/null || true
    fi
}

cleanup() {
    log_info "Restoring Coresight devices state..."
    if [ -n "$etf0_sink" ] && [ -f "$cs_base/tmc_etf0/enable_sink" ]; then
        echo "$etf0_sink" > "$cs_base/tmc_etf0/enable_sink" 2>/dev/null || true
    fi
    if [ -n "$etr0_sink" ] && [ -f "$cs_base/tmc_etr0/enable_sink" ]; then
        echo "$etr0_sink" > "$cs_base/tmc_etr0/enable_sink" 2>/dev/null || true
    fi
    if [ -n "$stm0_sink" ] && [ -f "$cs_base/stm0/enable_source" ]; then
        echo "$stm0_sink" > "$cs_base/stm0/enable_source" 2>/dev/null || true
    fi
}

trap cleanup EXIT

if [ ! -d "$cs_base" ]; then
    log_fail "Coresight directory not found: $cs_base"
    echo "$TESTNAME FAIL" > "$res_file"
    exit 1
fi

save_and_reset_devices

if [ -f "$cs_base/tmc_etf0/enable_sink" ]; then
    echo 1 > "$cs_base/tmc_etf0/enable_sink"
else
    log_warn "tmc_etf0 not found, proceeding without it..."
fi

cti_list=""
for _dev in "$cs_base"/cti*; do
    [ -e "$_dev" ] || continue
    cti_list="$cti_list $(basename "$_dev")"
done

if [ -z "$cti_list" ]; then
    log_fail "No CTI devices found."
    echo "$TESTNAME FAIL" > "$res_file"
    exit 1
else
    for cti in $cti_list; do
        dev_path="$cs_base/$cti"
        
        if [ ! -f "$dev_path/enable" ]; then
            log_warn "Skipping $cti: 'enable' node not found"
            continue
        fi

        log_info "Testing Device: $cti"

        if ! echo 1 > "$dev_path/enable"; then
            log_fail "$cti: Failed to write 1 to enable"
            fail_count=$((fail_count + 1))
            continue
        fi

        res=$(cat "$dev_path/enable")
        if [ "$res" -eq 1 ]; then
            log_pass "$cti Enabled Successfully"
        else
            log_fail "$cti Failed to Enable (Value: $res)"
            fail_count=$((fail_count + 1))
        fi

        if ! echo 0 > "$dev_path/enable"; then
            log_fail "$cti: Failed to write 0 to enable"
            fail_count=$((fail_count + 1))
            continue
        fi

        res=$(cat "$dev_path/enable")
        if [ "$res" -eq 0 ]; then
            log_pass "$cti Disabled Successfully"
        else
            log_fail "$cti Failed to Disable (Value: $res)"
            fail_count=$((fail_count + 1))
        fi
    done
fi

if [ "$fail_count" -eq 0 ]; then
    log_pass "CTI Enable/Disable Test Completed Successfully"
    echo "$TESTNAME PASS" > "$res_file"
else
    log_fail "CTI Enable/Disable Test Failed ($fail_count errors)"
    echo "$TESTNAME FAIL" > "$res_file"
fi

log_info "-------------------$TESTNAME Testcase Finished----------------------------"