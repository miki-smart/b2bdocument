# Realtime Features Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Technology:** WebSocket / SignalR  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [WebSocket Setup](#websocket-setup)
2. [Notification System](#notification-system)
3. [Real-time Updates](#real-time-updates)
4. [Connection Management](#connection-management)

---

## 🔌 WebSocket Setup

### SignalR Client

**File:** `src/shared/lib/signalr-client.ts`

```typescript
import * as signalR from '@microsoft/signalr';
import { useAuthStore } from '@/stores/auth-store';

class SignalRClient {
  private connection: signalR.HubConnection | null = null;

  async connect(): Promise<void> {
    const token = useAuthStore.getState().accessToken;
    
    this.connection = new signalR.HubConnectionBuilder()
      .withUrl(`${import.meta.env.VITE_WS_URL}/hub`, {
        accessTokenFactory: () => token || '',
      })
      .withAutomaticReconnect()
      .build();

    this.connection.onreconnecting(() => {
      console.log('Reconnecting to SignalR...');
    });

    this.connection.onreconnected(() => {
      console.log('Reconnected to SignalR');
    });

    this.connection.onclose(() => {
      console.log('SignalR connection closed');
    });

    await this.connection.start();
  }

  async disconnect(): Promise<void> {
    if (this.connection) {
      await this.connection.stop();
      this.connection = null;
    }
  }

  on(event: string, callback: (...args: any[]) => void): void {
    if (this.connection) {
      this.connection.on(event, callback);
    }
  }

  off(event: string, callback: (...args: any[]) => void): void {
    if (this.connection) {
      this.connection.off(event, callback);
    }
  }
}

export const signalRClient = new SignalRClient();
```

### Connection Hook

**File:** `src/shared/hooks/useSignalR.ts`

```typescript
import { useEffect } from 'react';
import { signalRClient } from '@/shared/lib/signalr-client';
import { useAuthStore } from '@/stores/auth-store';

export const useSignalR = () => {
  const { isAuthenticated } = useAuthStore();

  useEffect(() => {
    if (isAuthenticated) {
      signalRClient.connect().catch(console.error);
    }

    return () => {
      signalRClient.disconnect();
    };
  }, [isAuthenticated]);
};
```

---

## 🔔 Notification System

### Notification Store

**File:** `src/stores/notification-store.ts`

```typescript
import { create } from 'zustand';
import { signalRClient } from '@/shared/lib/signalr-client';

interface Notification {
  id: string;
  type: 'INFO' | 'SUCCESS' | 'WARNING' | 'ERROR';
  title: string;
  message: string;
  read: boolean;
  createdAt: string;
  link?: string;
}

interface NotificationState {
  notifications: Notification[];
  unreadCount: number;
  addNotification: (notification: Notification) => void;
  markAsRead: (id: string) => void;
  markAllAsRead: () => void;
  clear: () => void;
}

export const useNotificationStore = create<NotificationState>((set) => ({
  notifications: [],
  unreadCount: 0,

  addNotification: (notification) => {
    set((state) => ({
      notifications: [notification, ...state.notifications],
      unreadCount: state.unreadCount + 1,
    }));

    // Show toast
    toast[notification.type.toLowerCase()](notification.message);
  },

  markAsRead: (id) => {
    set((state) => ({
      notifications: state.notifications.map((n) =>
        n.id === id ? { ...n, read: true } : n
      ),
      unreadCount: Math.max(0, state.unreadCount - 1),
    }));
  },

  markAllAsRead: () => {
    set((state) => ({
      notifications: state.notifications.map((n) => ({ ...n, read: true })),
      unreadCount: 0,
    }));
  },

  clear: () => {
    set({ notifications: [], unreadCount: 0 });
  },
}));
```

### Notification Listener

**File:** `src/features/notifications/hooks/useNotificationListener.ts`

```typescript
import { useEffect } from 'react';
import { signalRClient } from '@/shared/lib/signalr-client';
import { useNotificationStore } from '@/stores/notification-store';

export const useNotificationListener = () => {
  const addNotification = useNotificationStore((state) => state.addNotification);

  useEffect(() => {
    const handleNotification = (data: any) => {
      addNotification({
        id: data.id,
        type: data.type,
        title: data.title,
        message: data.message,
        read: false,
        createdAt: data.createdAt,
        link: data.link,
      });
    };

    signalRClient.on('NotificationReceived', handleNotification);

    return () => {
      signalRClient.off('NotificationReceived', handleNotification);
    };
  }, [addNotification]);
};
```

### Notification Bell Component

**File:** `src/shared/components/layout/NotificationBell.tsx`

```typescript
export const NotificationBell = () => {
  const { notifications, unreadCount, markAsRead } = useNotificationStore();
  const [isOpen, setIsOpen] = useState(false);

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative">
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute top-0 right-0 h-4 w-4 bg-red-500 rounded-full text-xs text-white flex items-center justify-center">
              {unreadCount > 9 ? '9+' : unreadCount}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80">
        <div className="space-y-2">
          <div className="flex justify-between items-center">
            <h4 className="font-semibold">Notifications</h4>
            {unreadCount > 0 && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => markAllAsRead()}
              >
                Mark all read
              </Button>
            )}
          </div>
          <div className="max-h-96 overflow-y-auto space-y-2">
            {notifications.length === 0 ? (
              <p className="text-sm text-gray-500 text-center py-4">
                No notifications
              </p>
            ) : (
              notifications.map((notification) => (
                <div
                  key={notification.id}
                  className={`p-3 rounded border cursor-pointer hover:bg-gray-50 ${
                    !notification.read ? 'bg-blue-50' : ''
                  }`}
                  onClick={() => {
                    markAsRead(notification.id);
                    if (notification.link) {
                      navigate(notification.link);
                    }
                  }}
                >
                  <div className="flex justify-between items-start">
                    <div className="flex-1">
                      <p className="font-medium text-sm">{notification.title}</p>
                      <p className="text-xs text-gray-600 mt-1">
                        {notification.message}
                      </p>
                      <p className="text-xs text-gray-400 mt-1">
                        {formatRelativeTime(notification.createdAt)}
                      </p>
                    </div>
                    {!notification.read && (
                      <div className="h-2 w-2 bg-blue-600 rounded-full" />
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
};
```

---

## 🔄 Real-time Updates

### RFQ Bid Count Updates

```typescript
// In RFQ Detail Page
useEffect(() => {
  const handleBidUpdate = (data: { rfqId: string; bidCount: number }) => {
    if (data.rfqId === rfqId) {
      queryClient.setQueryData(['rfq', rfqId], (old: any) => ({
        ...old,
        bidCount: data.bidCount,
      }));
    }
  };

  signalRClient.on('BidCountUpdated', handleBidUpdate);

  return () => {
    signalRClient.off('BidCountUpdated', handleBidUpdate);
  };
}, [rfqId]);
```

### Contract Status Updates

```typescript
// In Contract Detail Page
useEffect(() => {
  const handleStatusUpdate = (data: {
    contractId: string;
    status: string;
  }) => {
    if (data.contractId === contractId) {
      queryClient.setQueryData(['contract', contractId], (old: any) => ({
        ...old,
        status: data.status,
      }));
    }
  };

  signalRClient.on('ContractStatusUpdated', handleStatusUpdate);

  return () => {
    signalRClient.off('ContractStatusUpdated', handleStatusUpdate);
  };
}, [contractId]);
```

### Wallet Balance Updates

```typescript
// In Wallet Page
useEffect(() => {
  const handleBalanceUpdate = (data: {
    walletId: string;
    balance: number;
    lockedBalance: number;
  }) => {
    if (data.walletId === walletId) {
      queryClient.setQueryData(['wallet', walletId], (old: any) => ({
        ...old,
        balance: data.balance,
        lockedBalance: data.lockedBalance,
        availableBalance: data.balance - data.lockedBalance,
      }));
    }
  };

  signalRClient.on('WalletBalanceUpdated', handleBalanceUpdate);

  return () => {
    signalRClient.off('WalletBalanceUpdated', handleBalanceUpdate);
  };
}, [walletId]);
```

---

## 🔌 Connection Management

### Auto-Reconnect

SignalR client automatically handles reconnection with exponential backoff.

### Connection Status Indicator

```typescript
export const ConnectionStatus = () => {
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    const checkConnection = () => {
      setIsConnected(signalRClient.connection?.state === signalR.HubConnectionState.Connected);
    };

    const interval = setInterval(checkConnection, 1000);
    return () => clearInterval(interval);
  }, []);

  if (isConnected) return null;

  return (
    <div className="fixed bottom-4 right-4 bg-yellow-500 text-white px-4 py-2 rounded shadow-lg">
      <div className="flex items-center gap-2">
        <Wifi className="h-4 w-4" />
        <span>Reconnecting...</span>
      </div>
    </div>
  );
};
```

---

## 📡 Event Types

### Business Events
- `BidReceived` - New bid on RFQ
- `BidAwarded` - Bid was awarded
- `ContractCreated` - Contract created
- `ContractActivated` - Contract activated
- `SettlementCompleted` - Settlement processed

### Provider Events
- `RFQPublished` - New RFQ published
- `BidAwarded` - Bid was awarded
- `VehicleAssignmentRequired` - Need to assign vehicles
- `DeliveryOTPGenerated` - OTP generated for delivery
- `SettlementCompleted` - Settlement processed

### Admin Events
- `VerificationSubmitted` - New verification pending
- `TransactionCompleted` - Transaction completed

---

**END OF REALTIME FEATURES GUIDE**

*For WebSocket server setup, refer to backend documentation*

