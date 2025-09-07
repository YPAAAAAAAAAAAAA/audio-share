-- Supabase Setup SQL for Audio Recording App
-- Run this in your Supabase SQL Editor: https://supabase.com/dashboard/project/wfxlihpxeeyjlllvoypa/sql

-- 1. Create users table
CREATE TABLE IF NOT EXISTS users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  device_id TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Create recordings table
CREATE TABLE IF NOT EXISTS recordings (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  duration INTEGER NOT NULL,
  file_url TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users(device_id);
CREATE INDEX IF NOT EXISTS idx_recordings_user_id ON recordings(user_id);
CREATE INDEX IF NOT EXISTS idx_recordings_created_at ON recordings(created_at DESC);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE recordings ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS policies for users table
CREATE POLICY "Users can view own data" ON users
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own data" ON users
  FOR INSERT WITH CHECK (true);

-- 6. Create RLS policies for recordings table
CREATE POLICY "Users can view all recordings" ON recordings
  FOR SELECT USING (true);

CREATE POLICY "Users can insert recordings" ON recordings
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update own recordings" ON recordings
  FOR UPDATE USING (user_id IN (SELECT id FROM users));

CREATE POLICY "Users can delete own recordings" ON recordings
  FOR DELETE USING (user_id IN (SELECT id FROM users));

-- 7. Grant permissions
GRANT ALL ON users TO anon;
GRANT ALL ON recordings TO anon;
GRANT ALL ON users TO authenticated;
GRANT ALL ON recordings TO authenticated;