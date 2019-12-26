#!/bin/bash

set -euxo pipefail
dub build --vverbose
pushd example
dub build --compiler=${DC} --vverbose
popd
# && dub test --build=unittest-cov --compiler=${DC}
