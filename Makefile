test-sc:
	@forge test --via-ir -vv

build:
	@forge build --via-ir

deploy:
	@forge script script/DeployEthAtomicSwap.s.sol:DeployEthAtomicSwap --via-ir -vv
