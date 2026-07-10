import sqlite3
import os
import uuid
from datetime import datetime, timedelta
import random

db_dir = os.path.expanduser('~/Library/Application Support/Anchored')
os.makedirs(db_dir, exist_ok=True)
db_path = os.path.join(db_dir, 'anchored.db')

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create table if not exists (just in case)
cursor.execute("""
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    type TEXT NOT NULL,
    appBundleID TEXT NOT NULL,
    appName TEXT NOT NULL,
    url TEXT,
    focusDurationSeconds INTEGER,
    sessionDurationSeconds INTEGER,
    distractionAppBundleID TEXT,
    distraction_domain TEXT,
    action TEXT,
    category TEXT,
    sessionGoal TEXT
)
""")

# Clear existing sessions so we can see the seeded ones clearly
cursor.execute("DELETE FROM sessions")

apps = [
    ("com.apple.dt.Xcode", "Xcode", "Development"),
    ("com.sublimetext.4", "Sublime Text", "Development"),
    ("com.googlecode.iterm2", "iTerm", "Development"),
    ("com.figma.Desktop", "Figma", "Design"),
    ("com.panic.Nova", "Nova", "Development")
]

distractions = [
    ("com.google.Chrome", "youtube.com"),
    ("com.google.Chrome", "twitter.com"),
    ("com.google.Chrome", "reddit.com"),
    ("com.google.Chrome", "facebook.com")
]

now = datetime.now()

# Insert events for the last 30 days
for day_offset in range(30):
    # Number of sessions for this day
    num_sessions = random.randint(1, 4)
    # Generate timestamp for this day
    day_date = now - timedelta(days=day_offset)
    
    for s in range(num_sessions):
        # Time of day (random hour between 9 and 18)
        session_time = day_date.replace(hour=random.randint(9, 18), minute=random.randint(0, 59), second=0, microsecond=0)
        
        # Pick app
        app_bundle, app_name, app_cat = random.choice(apps)
        
        # Duration: between 15 minutes (900s) and 3 hours (10800s)
        focus_duration = random.randint(900, 10800)
        
        # session_start event
        start_id = str(uuid.uuid4())
        cursor.execute("""
        INSERT INTO sessions (id, timestamp, type, appBundleID, appName, url, focusDurationSeconds, sessionDurationSeconds, action, category)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (start_id, session_time.isoformat(), 'session_start', app_bundle, app_name, None, 0, focus_duration, 'anchored', app_cat))
        
        # Let's say some sessions had distractions detected
        if random.random() < 0.4:
            dist_app, dist_domain = random.choice(distractions)
            dist_id = str(uuid.uuid4())
            dist_time = session_time + timedelta(seconds=random.randint(300, focus_duration - 100))
            cursor.execute("""
            INSERT INTO sessions (id, timestamp, type, appBundleID, appName, url, distractionAppBundleID, distraction_domain)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (dist_id, dist_time.isoformat(), 'distraction_detected', app_bundle, app_name, f"https://{dist_domain}", dist_app, dist_domain))
            
        # session_end event
        end_id = str(uuid.uuid4())
        end_time = session_time + timedelta(seconds=focus_duration)
        cursor.execute("""
        INSERT INTO sessions (id, timestamp, type, appBundleID, appName, url, focusDurationSeconds, sessionDurationSeconds, action, category)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (end_id, end_time.isoformat(), 'session_end', app_bundle, app_name, None, focus_duration, focus_duration, 'timeout', app_cat))

conn.commit()
conn.close()
print(f"Successfully seeded anchored.db at {db_path} with 30 days of mock data!")
