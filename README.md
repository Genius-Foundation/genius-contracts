## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Fund

**AVALANCHE**
```shell
source .env;
cast send 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc --value 0.2ether --rpc-url $AVALANCHE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0 --value 0.2ether --rpc-url $AVALANCHE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x90B29aF53D2bBb878cAe1952B773A307330393ef --value 0.2ether --rpc-url $AVALANCHE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26 --value 0.2ether --rpc-url $AVALANCHE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x5975fBa1186116168C479bb21Bb335f02D504CFB --value 0.2ether --rpc-url $AVALANCHE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;

**BASE**
```shell
source .env;
cast send 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc --value 0.0017ether --rpc-url $BASE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0 --value 0.0017ether --rpc-url $BASE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x90B29aF53D2bBb878cAe1952B773A307330393ef --value 0.0017ether --rpc-url $BASE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26 --value 0.0017ether --rpc-url $BASE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x5975fBa1186116168C479bb21Bb335f02D504CFB --value 0.0017ether --rpc-url $BASE_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
```

**ARBITRUM**
```shell
source .env;
cast send 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc --value 0.00066ether --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0 --value 0.00066ether --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x90B29aF53D2bBb878cAe1952B773A307330393ef --value 0.00066ether --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26 --value 0.00066ether --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x5975fBa1186116168C479bb21Bb335f02D504CFB --value 0.00066ether --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
```

**OPTIMISM**
```shell
source .env;
cast send 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc --value 0.00098ether --rpc-url $OPTIMISM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0 --value 0.00098ether --rpc-url $OPTIMISM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x90B29aF53D2bBb878cAe1952B773A307330393ef --value 0.00098ether --rpc-url $OPTIMISM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26 --value 0.00098ether --rpc-url $OPTIMISM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
cast send 0x5975fBa1186116168C479bb21Bb335f02D504CFB --value 0.00098ether --rpc-url $OPTIMISM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --confirmations 3;
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
