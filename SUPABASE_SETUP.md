# Supabase Cloud Sync Setup Guide

This guide walks you through setting up cloud sync for Neuro EMR.

## Overview

- **Offline-First**: App works fully offline, syncs when online
- **Role-Based Access**: Physicians (full), Nurses (vitals+demographics), Secretaries (appointments+demographics)
- **Real-Time Sync**: Changes sync across devices automatically
- **Rollback**: Run `git checkout v1.1-local-stable` to return to local-only version

---

## Step 1: Supabase Database Setup

1. Go to your Supabase Dashboard: https://supabase.com/dashboard
2. Select your project: **neuroemr**
3. Click **SQL Editor** in the left sidebar
4. Click **New Query**
5. Open the file `supabase_schema.sql` in this folder
6. Copy the entire contents and paste into the SQL editor
7. Click **Run** to execute

This creates all tables with Row Level Security policies.

---

## Step 2: Create Storage Bucket

1. In Supabase Dashboard, click **Storage** in the left sidebar
2. Click **New Bucket**
3. Name: `attachments`
4. Make it **Private** (not public)
5. Click **Create Bucket**

---

## Step 3: Get Your API Key

1. In Supabase Dashboard, click **Settings** (gear icon)
2. Click **API** in the submenu
3. Find **Project API keys**
4. Copy the **anon public** key (starts with `eyJ...`, very long)

---

## Step 4: Add Supabase Swift SDK to Xcode

1. Open the project in Xcode
2. File → **Add Package Dependencies...**
3. Enter URL: `https://github.com/supabase/supabase-swift`
4. Click **Add Package**
5. Select version **2.0.0** or later
6. Check **Supabase** product
7. Click **Add Package**

---

## Step 5: Configure Your API Key

1. Open `Second_EMRApp/Supabase/SupabaseConfig.swift`
2. Replace `YOUR_ANON_KEY_HERE` with your actual key:

```swift
static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

---

## Step 6: Build and Test

1. Build the project (⌘B)
2. Run the app
3. You should see the login screen
4. Create an account with your role
5. Test creating a patient on one device
6. Verify it appears on another device

---

## Role Permissions

| Role | Patients | Notes | Attachments | Vitals | Appointments | Physicians |
|------|----------|-------|-------------|--------|--------------|------------|
| **Physician** | Full | Full | Full | Full | Full | Full |
| **Nurse** | Create/Edit | View | View | Full | View | View |
| **Secretary** | Create/Edit | View | View | View | Full | View |

---

## Testing Offline Mode

1. Enable Airplane mode
2. Create or edit data
3. Notice the "offline" indicator
4. Disable Airplane mode
5. Data syncs automatically

---

## Troubleshooting

### "No such module 'Supabase'" Error
- Make sure you added the Swift package (Step 4)
- Clean build folder: Product → Clean Build Folder
- Restart Xcode

### "Authentication failed" Error
- Check your API key is correct (Step 3)
- Make sure you ran the SQL schema (Step 1)

### Data not syncing
- Check internet connection
- Verify Supabase project is running (Dashboard → Project → Status)
- Check for errors in Xcode console

---

## Files Created

| File | Purpose |
|------|---------|
| `supabase_schema.sql` | Database tables and RLS policies |
| `Supabase/SupabaseConfig.swift` | API configuration |
| `Supabase/SupabaseManager.swift` | All Supabase operations |
| `Supabase/SyncManager.swift` | Offline queue and sync |
| `Supabase/UserRole.swift` | Role permissions |
| `Supabase/AuthView.swift` | Login/Signup UI |

---

## Your Supabase Project

- **URL**: https://qboixtebfpwvunpqotls.supabase.co
- **Dashboard**: https://supabase.com/dashboard/project/qboixtebfpwvunpqotls

Find your anon key at: Settings → API → Project API keys → anon public
