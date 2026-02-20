#!/usr/bin/env node

/**
 * Proxy script to send messages from MiloOverlay to the main session
 * This ensures the message goes through the same session context as this conversation
 */

const https = require('https');
const http = require('http');

// Get message from command line
const message = process.argv[2];
if (!message) {
  console.error('Usage: send-to-main-session.js "message text"');
  process.exit(1);
}

// OpenClaw gateway configuration
const GATEWAY_TOKEN = 'a3092026f0ef038768367803d77d7d4136d1a4d2a3b73373';

// Voice-optimized system message
const voiceSystemMessage = `You are Milo responding via MiloOverlay voice interface. The user spoke to you and will hear your response via TTS. Keep responses concise and conversational (1-3 sentences unless more detail needed). No markdown, bullets, or code blocks - just natural speech. You should have full access to your memory about AJ's family (Veda, Mithila, Shal), work at Airbnb, and preferences.`;

async function sendToMainSession() {
  const payload = {
    model: "openclaw",
    messages: [
      { role: "system", content: voiceSystemMessage },
      { role: "user", content: message }
    ],
    max_tokens: 2048,
    stream: false,
    user: "telegram:7986763678"  // Force routing to main session
  };

  const data = JSON.stringify(payload);
  
  const options = {
    hostname: 'localhost',
    port: 18789,
    path: '/v1/chat/completions',
    method: 'POST',
    timeout: 30000,  // 30 second timeout
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data),
      'Authorization': `Bearer ${GATEWAY_TOKEN}`,
      'x-openclaw-agent-id': 'main'
    }
  };

  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      
      res.setTimeout(30000, () => {
        reject(new Error('Response timeout'));
      });
      
      res.on('data', chunk => {
        body += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = JSON.parse(body);
          if (response.choices && response.choices[0]?.message?.content) {
            // Clean up markdown and just output the content
            const content = response.choices[0].message.content
              .replace(/\*\*(.*?)\*\*/g, '$1')  // Remove bold markdown
              .replace(/\*(.*?)\*/g, '$1')      // Remove italic markdown
              .trim();
            console.log(content);
            resolve(content);
          } else {
            console.error('Unexpected response format:', body);
            reject(new Error('Invalid response format'));
          }
        } catch (err) {
          console.error('JSON parse error:', err);
          console.error('Raw response:', body);
          reject(err);
        }
      });
    });

    req.setTimeout(30000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    req.on('error', (err) => {
      console.error('Request error:', err);
      reject(err);
    });

    req.write(data);
    req.end();
  });
}

// Run with timeout
Promise.race([
  sendToMainSession(),
  new Promise((_, reject) => setTimeout(() => reject(new Error('Script timeout')), 35000))
]).catch(err => {
  console.error('Failed to send message:', err.message);
  process.exit(1);
});