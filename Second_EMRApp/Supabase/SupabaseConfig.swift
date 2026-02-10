//
//  SupabaseConfig.swift
//  Second_EMRApp
//
//  Supabase configuration and client initialization
//
//  SETUP INSTRUCTIONS:
//  1. In Xcode: File → Add Package Dependencies
//  2. Enter: https://github.com/supabase/supabase-swift
//  3. Select version 2.0.0 or later
//  4. Add "Supabase" product to your target
//  5. Replace YOUR_ANON_KEY_HERE with your actual anon key
//

import Foundation

#if canImport(Supabase)
import Supabase

enum SupabaseConfig {
    // MARK: - Credentials
    // TODO: Replace with your actual anon key from Supabase Dashboard → Settings → API
    static let projectURL = URL(string: "https://qboixtebfpwvunpqotls.supabase.co")!

    // The anon key should start with "eyJ..." and be ~200+ characters
    // Find it in Supabase Dashboard → Settings → API → Project API keys → anon public
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFib2l4dGViZnB3dnVucHFvdGxzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3MTcxNjUsImV4cCI6MjA4NjI5MzE2NX0.5VNa7rG7QbHcrW8PoaMNPdYIHmuPIsmUvLeyo3jKnuI"

    // MARK: - Client
    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey
    )

    // MARK: - Storage Bucket
    static let attachmentsBucket = "attachments"

    // MARK: - Validation
    static var isConfigured: Bool {
        anonKey != "YOUR_ANON_KEY_HERE" && (anonKey.hasPrefix("eyJ") || anonKey.hasPrefix("sb_"))
    }
}

#else

// Stub when Supabase SDK not installed
enum SupabaseConfig {
    static let projectURL = URL(string: "https://qboixtebfpwvunpqotls.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFib2l4dGViZnB3dnVucHFvdGxzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3MTcxNjUsImV4cCI6MjA4NjI5MzE2NX0.5VNa7rG7QbHcrW8PoaMNPdYIHmuPIsmUvLeyo3jKnuI"
    static let attachmentsBucket = "attachments"
    static var isConfigured: Bool { false }
}

#endif
