-- Storage Policies for Recordings Bucket
-- Run this in SQL Editor after creating the "recordings" bucket

-- Allow anyone to upload recordings
CREATE POLICY "Allow uploads" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'recordings');

-- Allow anyone to view recordings
CREATE POLICY "Allow public viewing" ON storage.objects
FOR SELECT USING (bucket_id = 'recordings');

-- Allow users to update their own recordings
CREATE POLICY "Allow updates" ON storage.objects
FOR UPDATE USING (bucket_id = 'recordings');

-- Allow users to delete their own recordings  
CREATE POLICY "Allow deletes" ON storage.objects
FOR DELETE USING (bucket_id = 'recordings');