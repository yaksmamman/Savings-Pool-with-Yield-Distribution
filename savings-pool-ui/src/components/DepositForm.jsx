import React, { useState } from 'react';
import { useAuth, useOpenContractCall, useAccount } from "@micro-stacks/react";
import { uintCV, principalCV} from '@stacks/transactions';



function DepositForm() {
  const [amount, setAmount] = useState('');
  const contractAddress = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"; // Local deployer address
  const contractName = "enhanced-savings-pool";
  const {openContractCall} = useOpenContractCall(); // Invoke as a hook here


  const handleDeposit = async () => {
    if (!amount) return alert('Enter an amount');
    await openContractCall({
      contractAddress: contractAddress,
      contractName: contractName,
      functionName: 'deposit',
      functionArgs: [uintCV(parseInt(amount))],
    });
    alert('Deposit successful!');
  };

  return (
    <div className="mb-8 p-4 border border-gray-600 rounded">
      <h2 className="text-lg font-semibold mb-2">Deposit</h2>
      <input
        type="number"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        className="w-full mb-4 p-2 border border-gray-700 rounded bg-gray-800"
        placeholder="Enter deposit amount"
      />
      <button
        onClick={handleDeposit}
        className="bg-green-600 px-4 py-2 rounded hover:bg-green-500 transition"
      >
        Deposit
      </button>
    </div>
  );
}

export default DepositForm;
