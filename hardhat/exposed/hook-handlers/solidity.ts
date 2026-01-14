import type { SolidityHooks, HookContext } from "hardhat/types/hooks";
import type { CompilerInput } from "hardhat/types/solidity";

export default async (): Promise<Partial<SolidityHooks>> => ({
  preprocessSolcInputBeforeBuilding: (
    context: HookContext,
    solcInput: CompilerInput,
    next: (
      nextContext: HookContext,
      nextSolcInput: CompilerInput,
    ) => Promise<CompilerInput>,
  ) : Promise<CompilerInput> => next(context, solcInput),
});