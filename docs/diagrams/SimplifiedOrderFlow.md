```mermaid
sequenceDiagram
    participant User
    participant Lit_Action as Lit Action (Orchestrator/Executor)
    participant Pool_Source as Pool Source Chain
    participant Pool_Dest as Pool Destination Chain

    User->>Lit_Action: Initiate cross-chain swap
    activate Lit_Action

    Lit_Action->>Pool_Source: addLiquiditySwap(trader, tokenIn, amountIn, destChainId, fillDeadline)
    activate Pool_Source
    Pool_Source-->>Lit_Action: Emit SwapDeposit event
    deactivate Pool_Source


    Lit_Action->>Pool_Dest: removeLiquiditySwap(order)
    activate Pool_Dest
    Pool_Dest-->>Lit_Action: Emit SwapWithdrawal event
    deactivate Pool_Dest

    Lit_Action->>Pool_Source: setOrderAsFilled(order)
    activate Pool_Source
    Pool_Source-->>Lit_Action: Emit OrderFilled event
    deactivate Pool_Source

    Lit_Action-->>User: Notify swap completion
    deactivate Lit_Action

    Note over User,Pool_Dest: Swap completed

    alt Order failed on dest chain and expires
        Lit_Action->>Pool_Source: revertOrder(order, targets, data, values)
        activate Pool_Source
        Pool_Source-->>Lit_Action: Emit OrderReverted event
        deactivate Pool_Source
        Lit_Action-->>User: Notify order revert and refund
    end
```