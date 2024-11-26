import { useState } from 'react';
import reactLogo from './assets/react.svg';
import './App.css';
import * as MicroStacks from '@micro-stacks/react';
import { WalletConnectButton } from './components/wallet-connect-button.jsx';
import { UserCard } from './components/user-card.jsx';
import { Logo } from './components/ustx-logo.jsx';
import { NetworkToggle } from './components/network-toggle.jsx';

import React from 'react';
import PoolStatus from './components/PoolStatus';
import DepositForm from './components/DepositForm';
import TransactionHistory from './components/TransactionHistory';
function Contents() {
  return (
    <>
  
      <div class="card">
        <UserCard />
        <WalletConnectButton />
        <NetworkToggle />
        <p
          style={{
            display: 'block',
            marginTop: '40px',
          }}
        >
        </p>
      </div>
    </>
  );
}

function App() {
  return (
    <MicroStacks.ClientProvider
    appName={'Savings Pool'}
    appIconUrl={reactLogo}
    >

    <div className="min-h-screen w-full bg-gradient-to-r from-gray-900 to-gray-800 text-white">
      <header className="p-4 flex justify-between items-center border-b border-gray-700">
        <h1 className="text-xl font-bold">Piggy Bank Pool</h1>
        <WalletConnectButton className="bg-blue-600 px-4 py-2 rounded hover:bg-blue-500 transition" />
      </header>
      <main className="p-8">
        <PoolStatus />
        <DepositForm />
        <TransactionHistory />
      </main>
    </div>
    </MicroStacks.ClientProvider>
  );
}

export default App;
