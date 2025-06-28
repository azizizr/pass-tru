const CACHE_VERSION = 'v2';
const CACHE_NAME = `passtru-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `passtru-dynamic-${CACHE_VERSION}`;

// Dynamic asset patterns
const CACHE_PATTERNS = [
  /\.(js|css|png|jpg|jpeg|gif|svg|woff|woff2)$/,
  /\/api\/events\//,
  /\/auth/,
  /\/checkin\//
];

// Core assets to cache immediately
const CORE_ASSETS = [
  '/',
  '/manifest.json',
  '/favicon.ico'
];

// Install event - cache core resources dynamically
self.addEventListener('install', (event) => {
  console.log('Service Worker installing...');
  
  event.waitUntil(
    Promise.all([
      caches.open(CACHE_NAME).then(cache => {
        console.log('Caching core assets');
        return cache.addAll(CORE_ASSETS);
      }),
      caches.open(DYNAMIC_CACHE)
    ]).then(() => {
      console.log('Core assets cached successfully');
      return self.skipWaiting();
    })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  console.log('Service Worker activating...');
  
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME && cacheName !== DYNAMIC_CACHE) {
            console.log('Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      console.log('Cache cleanup complete');
      return self.clients.claim();
    })
  );
});

// Fetch event - smart caching strategy
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);
  
  // Skip non-GET requests and chrome-extension requests
  if (request.method !== 'GET' || url.protocol === 'chrome-extension:') {
    return;
  }

  event.respondWith(
    handleRequest(request)
  );
});

async function handleRequest(request) {
  const url = new URL(request.url);
  const cacheStrategy = getCacheStrategy(url.pathname);
  
  switch (cacheStrategy) {
    case 'cache-first':
      return cacheFirstStrategy(request);
    case 'network-first':
      return networkFirstStrategy(request);
    case 'stale-while-revalidate':
    default:
      return staleWhileRevalidateStrategy(request);
  }
}

function getCacheStrategy(pathname) {
  // Static assets - cache first
  if (pathname.match(/\.(js|css|png|jpg|jpeg|gif|svg|woff|woff2)$/)) {
    return 'cache-first';
  }
  
  // API calls - network first
  if (pathname.startsWith('/api/')) {
    return 'network-first';
  }
  
  // Default strategy
  return 'stale-while-revalidate';
}

async function cacheFirstStrategy(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  
  if (cached) {
    return cached;
  }
  
  try {
    const response = await fetch(request);
    if (response.status === 200) {
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    console.error('Cache-first strategy failed:', error);
    return new Response('Offline', { status: 503 });
  }
}

async function networkFirstStrategy(request) {
  try {
    const response = await fetch(request);
    
    if (response.status === 200 && shouldCache(request.url)) {
      const cache = await caches.open(DYNAMIC_CACHE);
      cache.put(request, response.clone());
    }
    
    return response;
  } catch (error) {
    const cache = await caches.open(DYNAMIC_CACHE);
    const cached = await cache.match(request);
    
    if (cached) {
      return cached;
    }
    
    return new Response('Offline - No cached version available', { status: 503 });
  }
}

async function staleWhileRevalidateStrategy(request) {
  const cache = await caches.open(DYNAMIC_CACHE);
  const cached = await cache.match(request);
  
  // Always try to fetch in background
  const fetchPromise = fetch(request).then(response => {
    if (response.status === 200 && shouldCache(request.url)) {
      cache.put(request, response.clone());
    }
    return response;
  }).catch(() => null);
  
  // Return cached version immediately if available
  if (cached) {
    return cached;
  }
  
  // Otherwise wait for network
  const response = await fetchPromise;
  return response || new Response('Offline', { status: 503 });
}

function shouldCache(url) {
  return CACHE_PATTERNS.some(pattern => pattern.test(url));
}

// Background sync for offline check-ins
self.addEventListener('sync', (event) => {
  console.log('Background sync triggered:', event.tag);
  
  if (event.tag === 'background-sync') {
    event.waitUntil(doBackgroundSync());
  }
});

async function doBackgroundSync() {
  console.log('Performing background sync...');
  
  try {
    // Get pending check-ins from IndexedDB
    const pendingCheckins = await getPendingCheckins();
    console.log('Found pending check-ins:', pendingCheckins.length);
    
    for (const checkin of pendingCheckins) {
      try {
        await syncCheckin(checkin);
        await removePendingCheckin(checkin.id);
        console.log('Synced check-in:', checkin.id);
      } catch (error) {
        console.error('Failed to sync checkin:', checkin.id, error);
      }
    }
  } catch (error) {
    console.error('Background sync failed:', error);
  }
}

// Placeholder functions for IndexedDB operations
async function getPendingCheckins() {
  // In a real implementation, this would query IndexedDB
  const stored = localStorage.getItem('pendingCheckins');
  return stored ? JSON.parse(stored) : [];
}

async function syncCheckin(checkin) {
  // Implement actual sync logic
  const response = await fetch(`/api/checkin/${checkin.eventSlug}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uniqueId: checkin.uniqueId })
  });
  
  if (!response.ok) {
    throw new Error('Sync failed');
  }
  
  return response.json();
}

async function removePendingCheckin(id) {
  const stored = localStorage.getItem('pendingCheckins');
  if (stored) {
    const checkins = JSON.parse(stored);
    const filtered = checkins.filter(c => c.id !== id);
    localStorage.setItem('pendingCheckins', JSON.stringify(filtered));
  }
}

// Push notification handling with enhanced features
self.addEventListener('push', (event) => {
  console.log('Push notification received');
  
  const options = {
    body: event.data ? event.data.text() : 'New event update',
    icon: '/favicon.ico',
    badge: '/favicon.ico',
    vibrate: [100, 50, 100],
    data: {
      dateOfArrival: Date.now(),
      primaryKey: 1
    },
    actions: [
      {
        action: 'view',
        title: 'View Event',
        icon: '/favicon.ico'
      },
      {
        action: 'dismiss',
        title: 'Dismiss'
      }
    ],
    requireInteraction: true
  };

  event.waitUntil(
    self.registration.showNotification('PassTru Event', options)
  );
});

// Enhanced notification click handling
self.addEventListener('notificationclick', (event) => {
  console.log('Notification clicked:', event.action);
  
  event.notification.close();
  
  if (event.action === 'view') {
    event.waitUntil(
      clients.openWindow('/')
    );
  } else if (event.action === 'dismiss') {
    // Just close the notification
    return;
  } else {
    // Default action
    event.waitUntil(
      clients.openWindow('/')
    );
  }
});

// Cache warming for critical resources
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'WARM_CACHE') {
    event.waitUntil(warmCache(event.data.urls));
  }
});

async function warmCache(urls) {
  const cache = await caches.open(DYNAMIC_CACHE);
  
  for (const url of urls) {
    try {
      const response = await fetch(url);
      if (response.status === 200) {
        await cache.put(url, response);
        console.log('Warmed cache for:', url);
      }
    } catch (error) {
      console.error('Failed to warm cache for:', url, error);
    }
  }
}
