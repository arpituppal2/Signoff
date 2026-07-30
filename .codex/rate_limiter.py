#!/usr/bin/env python3
"""
Strict rate limiter: 30 RPM rolling max (well under 32/40 RPM limits).
Usage: python3 rate_limiter.py "your command here"
"""
import asyncio
import time
import sys
import subprocess
from collections import deque

RATE_LIMITER_STATE_FILE = "/tmp/signoff_rate_limiter_state.json"

class RateLimiter:
    def __init__(self, max_requests=30, window_seconds=60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests = deque()
        self.last_call = 0
        self.min_interval = 2.1  # Slightly over 2s to be safe
        self._load_state()
    
    def _load_state(self):
        try:
            import json
            with open(RATE_LIMITER_STATE_FILE, 'r') as f:
                data = json.load(f)
                now = time.time()
                # Restore only requests within the current window
                for ts in data.get('requests', []):
                    if ts > now - self.window_seconds:
                        self.requests.append(ts)
                self.last_call = data.get('last_call', 0)
        except:
            pass
    
    def _save_state(self):
        try:
            import json
            with open(RATE_LIMITER_STATE_FILE, 'w') as f:
                json.dump({
                    'requests': list(self.requests),
                    'last_call': self.last_call
                }, f)
        except:
            pass
    
    async def wait_if_needed(self):
        now = time.time()
        
        # Remove old requests outside the window
        while self.requests and self.requests[0] < now - self.window_seconds:
            self.requests.popleft()
        
        # Enforce minimum interval between calls
        elapsed = now - self.last_call
        if elapsed < self.min_interval:
            await asyncio.sleep(self.min_interval - elapsed)
            now = time.time()
        
        # If at limit, wait until oldest request expires
        if len(self.requests) >= self.max_requests:
            wait_time = self.requests[0] + self.window_seconds - now + 0.2
            if wait_time > 0:
                print(f"[RateLimiter] At {len(self.requests)}/{self.max_requests} RPM. Waiting {wait_time:.1f}s...")
                await asyncio.sleep(wait_time)
                now = time.time()
                # Re-clean after wait
                while self.requests and self.requests[0] < now - self.window_seconds:
                    self.requests.popleft()
        
        self.requests.append(now)
        self.last_call = now
        self._save_state()

async def main():
    if len(sys.argv) < 2:
        print("Usage: python3 rate_limiter.py \"command\"")
        sys.exit(1)
    
    limiter = RateLimiter(max_requests=30, window_seconds=60)
    await limiter.wait_if_needed()
    
    cmd = " ".join(sys.argv[1:])
    result = subprocess.run(cmd, shell=True)
    sys.exit(result.returncode)

if __name__ == "__main__":
    asyncio.run(main())
