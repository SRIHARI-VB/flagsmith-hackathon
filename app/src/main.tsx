import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import flagsmith from '@flagsmith/flagsmith';
import { FlagsmithProvider } from '@flagsmith/flagsmith/react';
import './index.css';
import App from './App.tsx';
import { FLAG, VARIANTS, getVisitorId } from './experiment';

const environmentID = import.meta.env.VITE_FLAGSMITH_ENVIRONMENT_ID as string | undefined;
const api = import.meta.env.VITE_FLAGSMITH_API_URL as string | undefined; // self-hosted only
const eventsApiUrl = import.meta.env.VITE_FLAGSMITH_EVENTS_URL as string | undefined; // self-hosted only

const visitorId = getVisitorId();

// Events are batched (every 10 s by default). Flush when the tab is hidden or
// closed, otherwise the last conversions of a short visit are lost.
const flush = () => void flagsmith.flushEvents?.();
addEventListener('pagehide', flush);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') flush();
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <FlagsmithProvider
      flagsmith={flagsmith}
      options={{
        environmentID,
        identity: visitorId, // same id for flag evaluation AND events
        enableEvents: true,
        ...(api ? { api } : {}),
        ...(eventsApiUrl ? { eventProcessorConfig: { eventsApiUrl } } : {}),
        // Used until flags load, or if Flagsmith is unreachable: everyone sees control.
        defaultFlags: { [FLAG]: { enabled: true, value: VARIANTS.control } },
        preventFetch: !environmentID, // lets the app run before Flagsmith is configured
        onError: (err) => console.warn('[flagsmith]', err),
      }}
    >
      <App visitorId={visitorId} offline={!environmentID} />
    </FlagsmithProvider>
  </StrictMode>,
);
