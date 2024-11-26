import React, { useEffect, useState } from 'react';
import { useAuth, useOpenContractCall, useAccount } from '@micro-stacks/react';

function PoolStatus() {
  const [status, setStatus] = useState({
    locked: false,
    totalDeposits: 0,
    totalYield: 0,
  });
  const contractAddress = 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM'; // Local deployer address
  const contractName = 'enhanced-savings-pool';
  const { openContractCall } = useOpenContractCall(); // Invoke as a hook here

  useEffect(() => {
    const fetchStatus = async () => {
      const result = await openContractCall({
        contractAddress: contractAddress,
        contractName: contractName,
        functionName: 'get-pool-status',
      });

      if (!result) {
        setStatus({
          locked: result.locked || false,
          totalDeposits: result.totalDeposits || 0,
          totalYield: result.totalYield || 0,
        });
      }

      // Process the result (assuming it's an object with keys)
      const parsedStatus = {
        locked: result.locked || false,
        totalDeposits: result.totalDeposits || 0,
        totalYield: result.totalYield || 0,
      };

      setStatus(parsedStatus);
    };
    fetchStatus();
  }, []);

  return (
    <div className="mb-8 p-4 border border-gray-600 rounded">
      <h2 className="text-lg font-semibold mb-2">Pool Status</h2>
      <p>Locked: {status.locked ? 'Yes' : 'No'}</p>
      <p>Total Deposits: {status.totalDeposits}</p>
      <p>Total Yield: {status.totalYield}</p>
    </div>
  );
}

export default PoolStatus;
