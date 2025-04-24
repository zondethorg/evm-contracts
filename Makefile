test-sc:
	@forge test --via-ir -vv

build:
	@forge build --via-ir

deploy:
	@forge script script/DeployEthAtomicSwap.s.sol:DeployEthAtomicSwap --via-ir -vv

deploy-mock-erc20:
	@forge script script/DeployMockERC20.s.sol:DeployMockERC20 --via-ir -vv --rpc-url http://localhost:9545
