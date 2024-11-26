import React from 'react';

function TransactionHistory() {
  const transactions = [
    { type: 'Deposit', amount: 100 },
    { type: 'Withdrawal', amount: 50 },
  ]; // Replace with dynamic data fetching

  return (
    <div className="p-4 border border-gray-600 rounded">
      <h2 className="text-lg font-semibold mb-2">Transaction History</h2>
      <ul>
        {transactions.map((tx, index) => (
          <li key={index} className="mb-2">
            {tx.type}: {tx.amount} STX
          </li>
        ))}
      </ul>
    </div>
  );
}

export default TransactionHistory;

