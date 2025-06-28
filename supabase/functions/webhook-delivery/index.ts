
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { webhook_id, event_type, payload } = await req.json()

    console.log(`Processing webhook delivery: ${webhook_id}, event: ${event_type}`)

    // Get webhook details
    const { data: webhook, error: webhookError } = await supabase
      .from('webhooks')
      .select('*')
      .eq('id', webhook_id)
      .eq('is_active', true)
      .single()

    if (webhookError || !webhook) {
      console.error('Webhook not found or inactive:', webhookError)
      return new Response(
        JSON.stringify({ error: 'Webhook not found or inactive' }),
        { 
          status: 404, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Check if this event type is subscribed
    if (!webhook.events.includes(event_type)) {
      console.log(`Event type ${event_type} not subscribed for webhook ${webhook.id}`)
      return new Response(
        JSON.stringify({ error: 'Event type not subscribed' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Create webhook signature
    const payloadString = JSON.stringify({
      id: crypto.randomUUID(),
      event_type,
      data: payload,
      timestamp: new Date().toISOString(),
      webhook_id: webhook.id
    })
    
    const encoder = new TextEncoder()
    const keyData = encoder.encode(webhook.secret)
    const payloadData = encoder.encode(payloadString)
    
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyData,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    )
    
    const signatureBuffer = await crypto.subtle.sign('HMAC', cryptoKey, payloadData)
    const signature = Array.from(new Uint8Array(signatureBuffer))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')

    console.log(`Delivering webhook to: ${webhook.url}`)

    // Deliver webhook
    const deliveryResult = await deliverWebhook(
      webhook.url,
      payloadString,
      signature,
      webhook.timeout_seconds || 30,
      webhook.retry_count || 3
    )

    console.log(`Webhook delivery result:`, deliveryResult)

    // Log delivery attempt
    await supabase
      .from('webhook_deliveries')
      .insert({
        webhook_id: webhook.id,
        event_type,
        payload: JSON.parse(payloadString),
        response_status: deliveryResult.status,
        response_body: deliveryResult.body,
        delivery_attempts: deliveryResult.attempts,
        delivered_at: deliveryResult.success ? new Date().toISOString() : null
      })

    // Update webhook last triggered timestamp
    await supabase
      .from('webhooks')
      .update({ last_triggered_at: new Date().toISOString() })
      .eq('id', webhook.id)

    return new Response(
      JSON.stringify({
        success: deliveryResult.success,
        status: deliveryResult.status,
        attempts: deliveryResult.attempts,
        webhook_id: webhook.id
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Webhook delivery error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }
})

async function deliverWebhook(
  url: string, 
  payload: string, 
  signature: string, 
  timeoutSeconds: number, 
  maxRetries: number
): Promise<{ success: boolean; status: number; body: string; attempts: number }> {
  let attempts = 0
  let lastError: any = null

  while (attempts < maxRetries) {
    attempts++
    
    try {
      console.log(`Webhook delivery attempt ${attempts}/${maxRetries} to ${url}`)
      
      const controller = new AbortController()
      const timeoutId = setTimeout(() => controller.abort(), timeoutSeconds * 1000)

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Webhook-Signature': `sha256=${signature}`,
          'X-Webhook-Timestamp': new Date().toISOString(),
          'User-Agent': 'Presto-Webhooks/1.0'
        },
        body: payload,
        signal: controller.signal
      })

      clearTimeout(timeoutId)

      const responseBody = await response.text()

      console.log(`Webhook response: ${response.status} ${response.statusText}`)

      if (response.ok) {
        return {
          success: true,
          status: response.status,
          body: responseBody,
          attempts
        }
      } else {
        lastError = `HTTP ${response.status}: ${responseBody}`
        console.log(`Webhook delivery failed: ${lastError}`)
      }

    } catch (error) {
      lastError = error.message
      console.log(`Webhook delivery attempt ${attempts} failed:`, error.message)
    }

    // Wait before retry (exponential backoff)
    if (attempts < maxRetries) {
      const backoffDelay = Math.min(Math.pow(2, attempts) * 1000, 30000) // Max 30 seconds
      console.log(`Waiting ${backoffDelay}ms before retry...`)
      await new Promise(resolve => setTimeout(resolve, backoffDelay))
    }
  }

  return {
    success: false,
    status: 0,
    body: lastError || 'Unknown error',
    attempts
  }
}
