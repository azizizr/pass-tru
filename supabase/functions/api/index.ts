
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
}

interface Database {
  public: {
    Functions: {
      validate_api_key: {
        Args: { api_key: string }
        Returns: {
          is_valid: boolean
          client_id: string
          permissions: any
          rate_limit_exceeded: boolean
        }[]
      }
      log_api_usage: {
        Args: {
          api_key: string
          endpoint: string
          method: string
          ip_address?: string
          user_agent?: string
          response_status?: number
          response_time_ms?: number
        }
        Returns: void
      }
    }
  }
}

serve(async (req) => {
  const startTime = Date.now()

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient<Database>(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const apiKey = req.headers.get('x-api-key')
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: 'API key required' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Validate API key
    const { data: validation, error: validationError } = await supabase.rpc('validate_api_key', {
      api_key: apiKey
    })

    if (validationError || !validation?.[0]?.is_valid) {
      return new Response(
        JSON.stringify({ error: 'Invalid API key' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    if (validation[0].rate_limit_exceeded) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded' }),
        { 
          status: 429, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    const url = new URL(req.url)
    const path = url.pathname.split('/').pop()
    let response: Response

    // Route API requests
    switch (path) {
      case 'events':
        response = await handleEventsAPI(req, supabase, validation[0].client_id)
        break
      case 'attendees':
        response = await handleAttendeesAPI(req, supabase, validation[0].client_id)
        break
      case 'checkin':
        response = await handleCheckinAPI(req, supabase, validation[0].client_id)
        break
      default:
        response = new Response(
          JSON.stringify({ error: 'Endpoint not found' }),
          { 
            status: 404, 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        )
    }

    // Log API usage
    const responseTime = Date.now() - startTime
    const clientIP = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip')
    const userAgent = req.headers.get('user-agent')

    await supabase.rpc('log_api_usage', {
      api_key: apiKey,
      endpoint: url.pathname,
      method: req.method,
      ip_address: clientIP,
      user_agent: userAgent,
      response_status: response.status,
      response_time_ms: responseTime
    })

    return response

  } catch (error) {
    console.error('API Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }
})

async function handleEventsAPI(req: Request, supabase: any, clientId: string): Promise<Response> {
  if (req.method === 'GET') {
    const { data: events, error } = await supabase
      .from('events')
      .select(`
        id, name, slug, date, venue, status, attendee_limit,
        client_events!inner(client_id)
      `)
      .eq('client_events.client_id', clientId)

    if (error) throw error

    return new Response(
      JSON.stringify({ events }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify({ error: 'Method not allowed' }),
    { 
      status: 405, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    }
  )
}

async function handleAttendeesAPI(req: Request, supabase: any, clientId: string): Promise<Response> {
  const url = new URL(req.url)
  const eventId = url.searchParams.get('event_id')

  if (!eventId) {
    return new Response(
      JSON.stringify({ error: 'event_id parameter required' }),
      { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }

  // Verify client has access to this event
  const { data: access } = await supabase
    .from('client_events')
    .select('id')
    .eq('client_id', clientId)
    .eq('event_id', eventId)
    .single()

  if (!access) {
    return new Response(
      JSON.stringify({ error: 'Access denied to this event' }),
      { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }

  if (req.method === 'GET') {
    const { data: attendees, error } = await supabase
      .from('attendees')
      .select('id, full_name, email, status, checked_in_at, unique_id')
      .eq('event_id', eventId)

    if (error) throw error

    return new Response(
      JSON.stringify({ attendees }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify({ error: 'Method not allowed' }),
    { 
      status: 405, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    }
  )
}

async function handleCheckinAPI(req: Request, supabase: any, clientId: string): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { 
        status: 405, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }

  const { attendee_id, event_id } = await req.json()

  if (!attendee_id || !event_id) {
    return new Response(
      JSON.stringify({ error: 'attendee_id and event_id required' }),
      { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }

  // Verify client has access to this event
  const { data: access } = await supabase
    .from('client_events')
    .select('id')
    .eq('client_id', clientId)
    .eq('event_id', event_id)
    .single()

  if (!access) {
    return new Response(
      JSON.stringify({ error: 'Access denied to this event' }),
      { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }

  // Check in the attendee
  const { data: attendee, error } = await supabase
    .from('attendees')
    .update({
      status: 'checked_in',
      checked_in_at: new Date().toISOString(),
      checkin_method: 'api'
    })
    .eq('id', attendee_id)
    .eq('event_id', event_id)
    .select()
    .single()

  if (error) throw error

  return new Response(
    JSON.stringify({ 
      success: true, 
      attendee: {
        id: attendee.id,
        full_name: attendee.full_name,
        status: attendee.status,
        checked_in_at: attendee.checked_in_at
      }
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}
