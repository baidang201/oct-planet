#!/bin/bash
set -eux

source set_env.sh

# Setup Hermes in packet relayer mode
killall hermes 2> /dev/null || true

tee ~/.hermes/config.toml<<EOF
[global]
log_level = "trace"
[mode]
[mode.clients]
enabled = true
refresh = true
misbehaviour = true
[mode.connections]
enabled = true
[mode.channels]
enabled = true
[mode.packets]
enabled = true
[[chains]]
account_prefix = "oct"
clock_drift = "5s"
gas_adjustment = 0.1
grpc_addr = "tcp://${CONSUMER_GRPC_ADDR}"
id = "$CONSUMER_CHAIN_ID"
key_name = "relayer"
max_gas = 2000000
rpc_addr = "http://${CONSUMER_RPC_LADDR}"
rpc_timeout = "10s"
store_prefix = "ibc"
trusting_period = "599s"
websocket_addr = "ws://${CONSUMER_RPC_LADDR}/websocket"
[chains.gas_price]
       denom = "stake"
       price = 0.00
[chains.trust_threshold]
       denominator = "3"
       numerator = "1"
[[chains]]
account_prefix = "cosmos"
clock_drift = "5s"
gas_adjustment = 0.1
grpc_addr = "tcp://${PROVIDER_GRPC_ADDR}"
id = "$PROVIDER_CHAIN_ID"
key_name = "relayer"
max_gas = 2000000
rpc_addr = "http://${PROVIDER_RPC_LADDR}"
rpc_timeout = "10s"
store_prefix = "ibc"
trusting_period = "599s"
websocket_addr = "ws://${PROVIDER_RPC_LADDR}/websocket"
[chains.gas_price]
       denom = "stake"
       price = 0.00
[chains.trust_threshold]
       denominator = "3"
       numerator = "1"
EOF

# Delete all previous keys in relayer
$HERMES_BINARY_PATH keys delete --chain $CONSUMER_CHAIN_ID --all
$HERMES_BINARY_PATH keys delete --chain $PROVIDER_CHAIN_ID --all

# Restore keys to hermes relayer
$HERMES_BINARY_PATH keys add --chain $CONSUMER_CHAIN_ID --mnemonic-file "$($JQ_BINARY_PATH -r .mnemonic $CONSUMER_HOME/consumer_keypair.json)"
# temp_start_provider.sh creates key pair and stores it in keypair.json
$HERMES_BINARY_PATH keys add --chain $PROVIDER_CHAIN_ID --mnemonic-file "$($JQ_BINARY_PATH -r .mnemonic $PROVIDER_HOME/keypair.json)"

sleep 5

$HERMES_BINARY_PATH create connection $CONSUMER_CHAIN_ID --client-a 07-tendermint-0 --client-b 07-tendermint-0
$HERMES_BINARY_PATH create channel $CONSUMER_CHAIN_ID --port-a consumer --port-b provider -o ordered --channel-version 1 connection-0

sleep 1

$HERMES_BINARY_PATH -j start &> ~/.hermes/logs &

############################################################

PROVIDER_VALIDATOR_ADDRESS=$($JQ_BINARY_PATH -r .address $PROVIDER_HOME/keypair.json)
DELEGATIONS=$($PROVIDER_BINARY_PATH q staking delegations $PROVIDER_VALIDATOR_ADDRESS --home $PROVIDER_HOME --node tcp://${PROVIDER_RPC_LADDR} -o json)
OPERATOR_ADDR=$(echo $DELEGATIONS | $JQ_BINARY_PATH -r .delegation_responses[0].delegation.validator_address)

$PROVIDER_BINARY_PATH tx staking delegate $OPERATOR_ADDR 50000000stake \
       --from $VALIDATOR \
       $KEYRING \
       --home $PROVIDER_HOME \
       --node tcp://${PROVIDER_RPC_LADDR} \
       --chain-id $PROVIDER_CHAIN_ID -y -b block
sleep 1