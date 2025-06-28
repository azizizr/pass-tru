import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { Resend } from "npm:resend@2.0.0";

const resend = new Resend(Deno.env.get("RESEND_API_KEY"));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface EmailRequest {
  to: string | string[];
  subject: string;
  template: 'welcome' | 'password_reset' | 'event_invite' | 'event_confirmation' | 'event_reminder' | 'custom_campaign';
  data: {
    name?: string;
    password?: string;
    event_name?: string;
    event_date?: string;
    event_venue?: string;
    login_url?: string;
    reset_url?: string;
    unique_id?: string;
    qr_code?: string;
    custom_message?: string;
    attendee_count?: number;
  };
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { to, subject, template, data }: EmailRequest = await req.json();

    let htmlContent = '';

    switch (template) {
      case 'welcome':
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); padding: 40px; text-align: center;">
              <div style="background: white; width: 60px; height: 60px; border-radius: 12px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-weight: bold; color: #3b82f6; font-size: 24px;">P</span>
              </div>
              <h1 style="color: white; margin: 0; font-size: 28px;">Welcome to PassTru</h1>
              <p style="color: rgba(255,255,255,0.9); margin: 10px 0 0; font-size: 16px;">Access Made Effortless</p>
            </div>
            <div style="background: white; padding: 40px; border-radius: 0 0 12px 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
              <h2 style="color: #1e293b; margin: 0 0 20px;">Hello ${data.name},</h2>
              <p style="color: #64748b; line-height: 1.6; margin: 0 0 20px;">
                Your PassTru account has been created successfully! You can now access the event management platform with the following credentials:
              </p>
              <div style="background: #f8fafc; padding: 20px; border-radius: 8px; margin: 20px 0;">
                <p style="margin: 0 0 10px; color: #1e293b;"><strong>Email:</strong> ${to}</p>
                <p style="margin: 0; color: #1e293b;"><strong>Password:</strong> ${data.password}</p>
              </div>
              <p style="color: #64748b; line-height: 1.6; margin: 20px 0;">
                For security reasons, please change your password after your first login.
              </p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="${data.login_url}" style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); color: white; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; display: inline-block;">
                  Access PassTru
                </a>
              </div>
              <p style="color: #94a3b8; font-size: 14px; margin: 30px 0 0; text-align: center;">
                If you have any questions, please contact our support team.
              </p>
            </div>
          </div>
        `;
        break;

      case 'event_confirmation':
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); padding: 40px; text-align: center;">
              <div style="background: white; width: 60px; height: 60px; border-radius: 12px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-weight: bold; color: #3b82f6; font-size: 24px;">P</span>
              </div>
              <h1 style="color: white; margin: 0; font-size: 28px;">Event Registration Confirmed</h1>
            </div>
            <div style="background: white; padding: 40px; border-radius: 0 0 12px 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
              <h2 style="color: #1e293b; margin: 0 0 20px;">Hello ${data.name},</h2>
              <p style="color: #64748b; line-height: 1.6; margin: 0 0 20px;">
                You have been successfully registered for the following event:
              </p>
              <div style="background: #f8fafc; padding: 20px; border-radius: 8px; margin: 20px 0;">
                <h3 style="margin: 0 0 15px; color: #1e293b; font-size: 20px;">${data.event_name}</h3>
                <p style="margin: 0 0 10px; color: #1e293b;"><strong>Date:</strong> ${data.event_date}</p>
                <p style="margin: 0 0 10px; color: #1e293b;"><strong>Venue:</strong> ${data.event_venue}</p>
                <p style="margin: 0; color: #1e293b;"><strong>Your ID:</strong> ${data.unique_id}</p>
              </div>
              <p style="color: #64748b; line-height: 1.6; margin: 20px 0;">
                Please bring this confirmation or present your unique ID at the event for check-in.
              </p>
              <p style="color: #94a3b8; font-size: 14px; margin: 30px 0 0; text-align: center;">
                Thank you for registering. We look forward to seeing you at the event!
              </p>
            </div>
          </div>
        `;
        break;

      case 'event_reminder':
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); padding: 40px; text-align: center;">
              <div style="background: white; width: 60px; height: 60px; border-radius: 12px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-weight: bold; color: #3b82f6; font-size: 24px;">P</span>
              </div>
              <h1 style="color: white; margin: 0; font-size: 28px;">Event Reminder</h1>
            </div>
            <div style="background: white; padding: 40px; border-radius: 0 0 12px 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
              <h2 style="color: #1e293b; margin: 0 0 20px;">Hello ${data.name},</h2>
              <p style="color: #64748b; line-height: 1.6; margin: 0 0 20px;">
                This is a friendly reminder about your upcoming event:
              </p>
              <div style="background: #f8fafc; padding: 20px; border-radius: 8px; margin: 20px 0;">
                <h3 style="margin: 0 0 15px; color: #1e293b; font-size: 20px;">${data.event_name}</h3>
                <p style="margin: 0 0 10px; color: #1e293b;"><strong>Date:</strong> ${data.event_date}</p>
                <p style="margin: 0 0 10px; color: #1e293b;"><strong>Venue:</strong> ${data.event_venue}</p>
                <p style="margin: 0; color: #1e293b;"><strong>Your ID:</strong> ${data.unique_id}</p>
              </div>
              <p style="color: #64748b; line-height: 1.6; margin: 20px 0;">
                Don't forget to bring your confirmation or present your unique ID for quick check-in.
              </p>
            </div>
          </div>
        `;
        break;

      case 'custom_campaign':
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); padding: 40px; text-align: center;">
              <div style="background: white; width: 60px; height: 60px; border-radius: 12px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-weight: bold; color: #3b82f6; font-size: 24px;">P</span>
              </div>
              <h1 style="color: white; margin: 0; font-size: 28px;">${data.event_name}</h1>
            </div>
            <div style="background: white; padding: 40px; border-radius: 0 0 12px 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
              <h2 style="color: #1e293b; margin: 0 0 20px;">Hello ${data.name},</h2>
              <div style="color: #64748b; line-height: 1.6; margin: 20px 0;">
                ${data.custom_message?.replace(/\n/g, '<br>') || ''}
              </div>
              <p style="color: #94a3b8; font-size: 14px; margin: 30px 0 0; text-align: center;">
                Best regards,<br>Event Management Team
              </p>
            </div>
          </div>
        `;
        break;

      case 'password_reset':
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); padding: 40px; text-align: center;">
              <div style="background: white; width: 60px; height: 60px; border-radius: 12px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-weight: bold; color: #3b82f6; font-size: 24px;">P</span>
              </div>
              <h1 style="color: white; margin: 0; font-size: 28px;">Password Reset</h1>
            </div>
            <div style="background: white; padding: 40px; border-radius: 0 0 12px 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
              <h2 style="color: #1e293b; margin: 0 0 20px;">Hello ${data.name},</h2>
              <p style="color: #64748b; line-height: 1.6; margin: 0 0 20px;">
                We received a request to reset your PassTru account password. Click the button below to create a new password:
              </p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="${data.reset_url}" style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); color: white; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; display: inline-block;">
                  Reset Password
                </a>
              </div>
              <p style="color: #94a3b8; font-size: 14px; margin: 30px 0 0; text-align: center;">
                If you didn't request this password reset, please ignore this email. The link will expire in 24 hours.
              </p>
            </div>
          </div>
        `;
        break;

      case 'event_invite':
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); padding: 40px; text-align: center;">
              <div style="background: white; width: 60px; height: 60px; border-radius: 12px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-weight: bold; color: #3b82f6; font-size: 24px;">P</span>
              </div>
              <h1 style="color: white; margin: 0; font-size: 28px;">Event Assignment</h1>
            </div>
            <div style="background: white; padding: 40px; border-radius: 0 0 12px 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
              <h2 style="color: #1e293b; margin: 0 0 20px;">Hello ${data.name},</h2>
              <p style="color: #64748b; line-height: 1.6; margin: 0 0 20px;">
                You have been assigned to manage the following event:
              </p>
              <div style="background: #f8fafc; padding: 20px; border-radius: 8px; margin: 20px 0; text-align: center;">
                <h3 style="margin: 0; color: #1e293b; font-size: 20px;">${data.event_name}</h3>
              </div>
              <p style="color: #64748b; line-height: 1.6; margin: 20px 0;">
                You can now access the event management dashboard to handle attendee check-ins, view reports, and manage event details.
              </p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="${data.login_url}" style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); color: white; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; display: inline-block;">
                  Access Event Dashboard
                </a>
              </div>
            </div>
          </div>
        `;
        break;

      default:
        throw new Error('Invalid email template');
    }

    // Handle both single and bulk email sending
    const recipients = Array.isArray(to) ? to : [to];
    const emailPromises = recipients.map(recipient => 
      resend.emails.send({
        from: "PassTru <noreply@passtru.com>",
        to: [recipient],
        subject: subject,
        html: htmlContent,
      })
    );

    const emailResponses = await Promise.all(emailPromises);
    console.log("Emails sent successfully:", emailResponses);

    return new Response(JSON.stringify({ 
      success: true, 
      sent: recipients.length,
      responses: emailResponses 
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    });
  } catch (error: any) {
    console.error("Error in send-email function:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      }
    );
  }
};

serve(handler);
