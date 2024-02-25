//
//  Supabase.swift
//  Remember
//
//  Created by Louis Beaumont on 17/02/2024.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
  supabaseURL: URL(string: supabaseUrl)!,
  supabaseKey: supabaseAnonApiKey
)
