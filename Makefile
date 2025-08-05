.PHONY: all build test clean deploy-local-contracts deploy-testnet-contracts deploy-mainnet-contracts deploy-polygon-contracts deploy-libraries deploy-holesky-contracts deploy-factory-testnet deploy-factory-polygon deploy-factory-holesky deploy-factory-mainnet deploy-all-factory-testnet deploy-all-factory-polygon deploy-all-factory-holesky deploy-all-factory-mainnet deploy-all-factory-base deploy-factory-base deploy-libraries-base deploy-base-contracts deploy-all-base deploy-arbitrum-contracts deploy-bsc-contracts deploy-libraries-arbitrum deploy-libraries-bsc deploy-factory-arbitrum deploy-factory-bsc deploy-all-factory-arbitrum deploy-all-factory-bsc deploy-all-arbitrum deploy-all-bsc update-implementations-arbitrum update-implementations-bsc verify help swap-tokens deploy-implementations-local deploy-implementations-testnet deploy-implementations-polygon deploy-implementations-holesky deploy-implementations-base deploy-implementations-arbitrum deploy-implementations-bsc deploy-implementations-mainnet
include .env

LOCAL_RPC_URL := http://127.0.0.1:8545
TESTNET_RPC := ${RPC_URL_TESTNET}
MAINNET_RPC := ${RPC_URL_MAINNET}
POLYGON_RPC := ${RPC_URL_POLYGON}
HOLESKY_RPC := ${RPC_URL_HOLESKY}
BASE_RPC := ${RPC_URL_BASE}
ARBITRUM_RPC := ${RPC_URL_ARBITRUM}
BSC_RPC := ${RPC_URL_BSC}
DEPLOY_SCRIPT := script/MainVault.s.sol
LIBRARIES_SCRIPT := script/DeployLibraries.s.sol
FACTORY_SCRIPT := script/Factory.s.sol
PRIVATE_KEY := ${PRIVATE_KEY}
CHAIN_ID := 137

# Проверяем наличие файла с адресами библиотек
ifneq ("$(wildcard ./.library_addresses.env)","")
  include ./.library_addresses.env
endif

UPDATE_IMPLEMENTATIONS_SCRIPT := script/UpdateImplementations.s.sol
DEPLOY_IMPLEMENTATIONS_SCRIPT := script/DeployImplementations.s.sol

all: help

build:
	@echo "Building contracts..."
	forge build

test:
	@echo "Running tests..."
	forge test -vvv

deploy-libraries-testnet:
	forge clean
	@echo "Deploying libraries to testnet..."
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-libraries-polygon:
	@echo "Deploying libraries to Polygon network..."
	forge clean
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-libraries-holesky:
	@echo "Deploying libraries to Holesky test network..."
	forge clean
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${HOLESKY_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-libraries-mainnet:
	forge clean
	@echo "Deploying libraries to Mainnet..."
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-libraries-base:
	@echo "Deploying libraries to Base network..."
	forge clean
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${BASE_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--verifier etherscan \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-libraries-arbitrum:
	@echo "Deploying libraries to Arbitrum network..."
	forge clean
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${ARBITRUM_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--verifier etherscan \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-libraries-bsc:
	@echo "Deploying libraries to BSC network..."
	forge clean
	forge script ${LIBRARIES_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	else \
		echo "Warning: ./.library_addresses.env file was not created"; \
	fi

deploy-local-contracts:
	forge clean
	forge script ${DEPLOY_SCRIPT} --rpc-url ${LOCAL_RPC_URL} --broadcast --private-key ${PRIVATE_KEY} -vvv

deploy-local-factory:
	forge clean
	forge script ${FACTORY_SCRIPT} --rpc-url ${LOCAL_RPC_URL} --broadcast --private-key ${PRIVATE_KEY} -vvv

deploy-testnet-contracts: 
	forge clean
	@echo "Deploying to testnet..."
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-polygon-contracts:
	forge clean
	@echo "Deploying to Polygon network..."
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

deploy-holesky-contracts:
	forge clean
	@echo "Deploying to Holesky test network..."
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${HOLESKY_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-mainnet-contracts:
	forge clean
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Деплой MainVaultFactory в тестовую сеть
deploy-factory-testnet:
	forge clean
	@echo "Deploying MainVaultFactory to testnet..."
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Деплой MainVaultFactory в Polygon
deploy-factory-polygon:
	forge clean
	@echo "Deploying MainVaultFactory to Polygon network..."
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

# Деплой MainVaultFactory в Holesky
deploy-factory-holesky:
	forge clean
	@echo "Deploying MainVaultFactory to Holesky test network..."
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${HOLESKY_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Деплой MainVaultFactory в основную сеть
deploy-factory-mainnet:
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Деплой MainVaultFactory в Base
deploy-factory-base:
	forge clean
	@echo "Deploying MainVaultFactory to Base network..."
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${BASE_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Деплой MainVaultFactory в Arbitrum
deploy-factory-arbitrum:
	forge clean
	@echo "Deploying MainVaultFactory to Arbitrum network..."
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${ARBITRUM_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Деплой MainVaultFactory в BSC
deploy-factory-bsc:
	forge clean
	@echo "Deploying MainVaultFactory to BSC network..."
	forge script ${FACTORY_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

# Комбинированные цели для деплоя библиотек и фабрики
deploy-all-factory-testnet: deploy-libraries-testnet deploy-factory-testnet

deploy-all-factory-polygon: deploy-libraries-polygon deploy-factory-polygon

deploy-all-factory-holesky: deploy-libraries-holesky deploy-factory-holesky

deploy-all-factory-mainnet: deploy-libraries-mainnet deploy-factory-mainnet

deploy-all-factory-base: deploy-libraries-base deploy-factory-base

deploy-all-factory-arbitrum: deploy-libraries-arbitrum deploy-factory-arbitrum

deploy-all-factory-bsc: deploy-libraries-bsc deploy-factory-bsc

deploy-all-testnet: deploy-libraries-testnet deploy-testnet-contracts

deploy-all-polygon: deploy-libraries-polygon deploy-polygon-contracts

deploy-all-holesky: deploy-libraries-holesky deploy-holesky-contracts

deploy-all-base: deploy-libraries-base deploy-base-contracts

deploy-all-arbitrum: deploy-libraries-arbitrum deploy-arbitrum-contracts

deploy-all-bsc: deploy-libraries-bsc deploy-bsc-contracts

verify:
	@echo "Verifying a contract manually..."
	@echo "Please enter the contract address to verify:"
	@read -p "Contract address: " contract_address; \
	echo "Please enter the contract name (MainVault, InvestmentVault, or ERC1967Proxy):"; \
	read -p "Contract name: " contract_name; \
	forge verify-contract $$contract_address $$contract_name  --rpc-url ${POLYGON_RPC} --chain-id ${CHAIN_ID} --etherscan-api-key ${POLYGONSCAN_API_KEY}

clean:
	@echo "Cleaning build artifacts..."
	forge clean

swap-tokens:
	@echo "Executing token swap..."
	forge script script/SwapTokens.s.sol:SwapTokensScript \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

deploy-base-contracts:
	forge clean
	@echo "Deploying to Base network..."
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${BASE_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-arbitrum-contracts:
	forge clean
	@echo "Deploying to Arbitrum network..."
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${ARBITRUM_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-bsc-contracts:
	forge clean
	@echo "Deploying to BSC network..."
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv



deploy-all-factory-base: deploy-libraries-base deploy-factory-base

deploy-all-base: deploy-libraries-base deploy-base-contracts

grant-role-polygon:
	forge script script/GrantRole.s.sol:GrantRoleScript \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

# Update implementations commands
update-implementations-testnet:
	forge clean
	@echo "Updating implementations in testnet..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

update-implementations-polygon:
	forge clean
	@echo "Updating implementations in Polygon network..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

update-implementations-holesky:
	forge clean
	@echo "Updating implementations in Holesky test network..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${HOLESKY_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

update-implementations-base:
	forge clean
	@echo "Updating implementations in Base network..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${BASE_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

update-implementations-arbitrum:
	forge clean
	@echo "Updating implementations in Arbitrum network..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${ARBITRUM_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

update-implementations-bsc:
	forge clean
	@echo "Updating implementations in BSC network..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

update-implementations-mainnet:
	forge clean
	@echo "Updating implementations in Mainnet..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

# Deploy implementations commands
deploy-implementations-local:
	forge clean
	@echo "Deploying implementations to local network..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

deploy-implementations-testnet:
	forge clean
	@echo "Deploying implementations to testnet..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-implementations-polygon:
	forge clean
	@echo "Deploying implementations to Polygon network..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

deploy-implementations-holesky:
	forge clean
	@echo "Deploying implementations to Holesky test network..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${HOLESKY_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-implementations-base:
	forge clean
	@echo "Deploying implementations to Base network..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${BASE_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-implementations-arbitrum:
	forge clean
	@echo "Deploying implementations to Arbitrum network..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${ARBITRUM_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

deploy-implementations-bsc:
	forge clean
	@echo "Deploying implementations to BSC network..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		--legacy \
		-vvv

deploy-implementations-mainnet:
	forge clean
	@echo "Deploying implementations to Mainnet..."
	forge script ${DEPLOY_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--libraries src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary:${mainVaultSwapLibrary} \
		--libraries src/utils/SwapLibrary.sol:SwapLibrary:${swapLibrary} \
		--libraries src/utils/Constants.sol:Constants:${constantsLibrary} \
		-vvv

update-implementations-local:
	forge clean
	@echo "Updating implementations in local network..."
	forge script ${UPDATE_IMPLEMENTATIONS_SCRIPT} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

help:
	@echo "Available commands:"
	@echo "  make build          - Build contracts"
	@echo "  make test           - Run tests"
	@echo "  make deploy-libraries-testnet - Deploy libraries to testnet"
	@echo "  make deploy-libraries-polygon - Deploy libraries to Polygon"
	@echo "  make deploy-libraries-holesky - Deploy libraries to Holesky"
	@echo "  make deploy-libraries-base - Deploy libraries to Base"
	@echo "  make deploy-libraries-arbitrum - Deploy libraries to Arbitrum"
	@echo "  make deploy-libraries-bsc - Deploy libraries to BSC"
	@echo "  make deploy-libraries-mainnet - Deploy libraries to Mainnet (use with caution!)"
	@echo "  make deploy-local-contracts   - Deploy contracts to local network"
	@echo "  make deploy-local-factory   - Deploy factory to local network"
	@echo "  make deploy-testnet-contracts - Deploy to testnet with verification"
	@echo "  make deploy-polygon-contracts - Deploy to Polygon network with verification"
	@echo "  make deploy-holesky-contracts - Deploy to Holesky test network with verification"
	@echo "  make deploy-base-contracts - Deploy to Base network with verification"
	@echo "  make deploy-arbitrum-contracts - Deploy to Arbitrum network with verification"
	@echo "  make deploy-bsc-contracts - Deploy to BSC network with verification"
	@echo "  make deploy-mainnet-contracts - Deploy to mainnet with verification (use with caution!)"
	@echo "  make deploy-factory-testnet - Deploy MainVaultFactory to testnet with verification"
	@echo "  make deploy-factory-polygon - Deploy MainVaultFactory to Polygon with verification"
	@echo "  make deploy-factory-holesky - Deploy MainVaultFactory to Holesky with verification"
	@echo "  make deploy-factory-base - Deploy MainVaultFactory to Base with verification"
	@echo "  make deploy-factory-arbitrum - Deploy MainVaultFactory to Arbitrum with verification"
	@echo "  make deploy-factory-bsc - Deploy MainVaultFactory to BSC with verification"
	@echo "  make deploy-factory-mainnet - Deploy MainVaultFactory to mainnet with verification (use with caution!)"
	@echo "  make deploy-all-testnet - Deploy libraries and contracts to testnet"
	@echo "  make deploy-all-polygon - Deploy libraries and contracts to Polygon"
	@echo "  make deploy-all-holesky - Deploy libraries and contracts to Holesky"
	@echo "  make deploy-all-base - Deploy libraries and contracts to Base"
	@echo "  make deploy-all-arbitrum - Deploy libraries and contracts to Arbitrum"
	@echo "  make deploy-all-bsc - Deploy libraries and contracts to BSC"
	@echo "  make deploy-all-factory-testnet - Deploy libraries and factory to testnet"
	@echo "  make deploy-all-factory-polygon - Deploy libraries and factory to Polygon"
	@echo "  make deploy-all-factory-holesky - Deploy libraries and factory to Holesky"
	@echo "  make deploy-all-factory-base - Deploy libraries and factory to Base"
	@echo "  make deploy-all-factory-arbitrum - Deploy libraries and factory to Arbitrum"
	@echo "  make deploy-all-factory-bsc - Deploy libraries and factory to BSC"
	@echo "  make deploy-all-factory-mainnet - Deploy libraries and factory to mainnet (use with caution!)"
	@echo "  make deploy-implementations-local - Deploy implementations to local network"
	@echo "  make deploy-implementations-testnet - Deploy implementations to testnet with verification"
	@echo "  make deploy-implementations-polygon - Deploy implementations to Polygon with verification"
	@echo "  make deploy-implementations-holesky - Deploy implementations to Holesky with verification"
	@echo "  make deploy-implementations-base - Deploy implementations to Base with verification"
	@echo "  make deploy-implementations-arbitrum - Deploy implementations to Arbitrum with verification"
	@echo "  make deploy-implementations-bsc - Deploy implementations to BSC with verification"
	@echo "  make deploy-implementations-mainnet - Deploy implementations to mainnet with verification (use with caution!)"
	@echo "  make update-implementations-local - Update implementations in local network"
	@echo "  make update-implementations-testnet - Update implementations in testnet with verification"
	@echo "  make update-implementations-polygon - Update implementations in Polygon with verification"
	@echo "  make update-implementations-holesky - Update implementations in Holesky with verification"
	@echo "  make update-implementations-base - Update implementations in Base with verification"
	@echo "  make update-implementations-arbitrum - Update implementations in Arbitrum with verification"
	@echo "  make update-implementations-bsc - Update implementations in BSC with verification"
	@echo "  make update-implementations-mainnet - Update implementations in mainnet with verification (use with caution!)"
	@echo "  make verify         - Manually verify a contract on Etherscan"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make swap-tokens    - Execute token swap via InvestmentVault"
	@echo "  make help           - Show this help message"
	@echo ""
	@echo "Before deploying, make sure to set up the required environment variables in .env file."
	@echo ""
	@echo "For updating implementations, set FACTORY_ADDRESS in your .env file."
	@echo "Optional flags: DEPLOY_MAIN_VAULT, DEPLOY_INVESTMENT_VAULT, DEPLOY_AGENT_DISTRIBUTION (default: true)" 