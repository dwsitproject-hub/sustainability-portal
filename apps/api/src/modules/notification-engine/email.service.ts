import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import type { Transporter } from 'nodemailer';
import { getEmailThemeFromTokens } from '../../config/email-theme';
import { renderBaseEmailTemplate } from './templates/base-email.template';

export interface EmailOptions {
  to: string | string[];
  subject: string;
  text?: string;
  html?: string;
}

@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);
  private transporter: Transporter;

  constructor(private configService: ConfigService) {
    this.createTransporter();
  }

  private createTransporter(): void {
    const host = String(this.configService.get('SMTP_HOST', '') ?? '').trim();
    const port = Number(this.configService.get('SMTP_PORT', 587));
    const secure = this.configService.get('SMTP_SECURE', 'false') === 'true';
    const user = this.configService.get('SMTP_USER', '');
    const pass = this.configService.get('SMTP_PASS', '');

    if (!host) {
      this.logger.warn(
        'SMTP_HOST is not set. Password-reset and verification emails will fail until SMTP is configured.',
      );
    }

    this.transporter = nodemailer.createTransport({
      host: host || 'localhost',
      port: Number.isFinite(port) ? port : 587,
      secure,
      auth: user && pass ? { user, pass } : undefined,
      connectionTimeout: this.configService.get<number>('SMTP_TIMEOUT_MS', 10000),
      greetingTimeout: this.configService.get<number>('SMTP_GREETING_TIMEOUT_MS', 10000),
      socketTimeout: this.configService.get<number>('SMTP_SOCKET_TIMEOUT_MS', 20000),
    });

    this.logger.log(
      `Email transporter configured: ${host || 'localhost'}:${Number.isFinite(port) ? port : 587}`,
    );
  }

  async sendEmail(options: EmailOptions): Promise<boolean> {
    const mailFromName = this.configService.get<string>('MAIL_FROM_NAME');
    const mailFromAddress = this.configService.get<string>('MAIL_FROM_ADDRESS');
    const from =
      mailFromName && mailFromAddress
        ? `${mailFromName} <${mailFromAddress}>`
        : this.configService.get(
            'SMTP_FROM',
            'SLMS Notifications <noreply@slms.local>',
          );

    try {
      const result = await this.transporter.sendMail({
        from,
        to: Array.isArray(options.to) ? options.to.join(', ') : options.to,
        subject: options.subject,
        text: options.text,
        html: options.html,
      });

      this.logger.log(`Email sent successfully (messageId: ${result.messageId})`);
      return true;
    } catch (error) {
      const err = error as Error;
      this.logger.error(
        `Failed to send email to ${Array.isArray(options.to) ? options.to.join(', ') : options.to}: ${err?.message ?? error}`,
        err?.stack,
      );
      return false;
    }
  }

  async sendExpiryNotification(
    to: string,
    itemType: string,
    itemName: string,
    daysRemaining: number,
    expiryDate: string,
  ): Promise<boolean> {
    const urgencyLevel =
      daysRemaining <= 30 ? 'URGENT' : daysRemaining <= 60 ? 'WARNING' : 'REMINDER';

    const subject = `[${urgencyLevel}] ${itemType} Expiring in ${daysRemaining} Days: ${itemName}`;

    const theme = getEmailThemeFromTokens();
    const webUrl = this.configService.get('WEB_URL', 'http://localhost:3000');
    const daysColor = daysRemaining <= 30 ? theme.primary : theme.text;

    const contentHtml = `
<p style="margin: 0 0 16px 0;">Dear User,</p>
<p style="margin: 0 0 16px 0;">This is a reminder that the following ${itemType.toLowerCase()} will expire soon:</p>
<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="width: 100%; margin: 16px 0; background: #F4F4F4; border-radius: ${theme.radius}; border: 1px solid ${theme.border};">
  <tr>
    <td style="padding: 12px 16px; font-weight: bold; width: 40%; color: ${theme.text};">${itemType} Name:</td>
    <td style="padding: 12px 16px; color: ${theme.text};"><strong>${itemName}</strong></td>
  </tr>
  <tr>
    <td style="padding: 12px 16px; font-weight: bold; color: ${theme.text};">Expiry Date:</td>
    <td style="padding: 12px 16px; color: ${theme.text};"><strong>${expiryDate}</strong></td>
  </tr>
  <tr>
    <td style="padding: 12px 16px; font-weight: bold; color: ${theme.text};">Days Remaining:</td>
    <td style="padding: 12px 16px;"><strong style="color: ${daysColor};">${daysRemaining} days</strong></td>
  </tr>
</table>
<p style="margin: 0 0 16px 0;"><strong>Action Required:</strong> Please review and renew this ${itemType.toLowerCase()} before it expires to ensure compliance.</p>
`.trim();

    const html = renderBaseEmailTemplate({
      headerTitle: `[${urgencyLevel}] ${itemType} Expiration Notice`,
      logoUrl: `${String(webUrl).replace(/\/$/, '')}/logo.png`,
      greeting: 'Dear User,',
      subtitle: `This is a reminder that the following ${itemType.toLowerCase()} will expire soon.`,
      contentHtml,
      cta: { text: 'View in SLMS Portal', url: webUrl },
      footerText:
        'This is an automated notification from the Sustainability Licensing Management System (SLMS). If you have questions, please contact your system administrator. Please do not reply to this email.',
      previewText: `${urgencyLevel}: ${itemType} expiring in ${daysRemaining} days - ${itemName}`,
    });

    const text = `
${urgencyLevel}: ${itemType} Expiring in ${daysRemaining} Days

Dear User,

This is a reminder that the following ${itemType.toLowerCase()} will expire soon:

${itemType} Name: ${itemName}
Expiry Date: ${expiryDate}
Days Remaining: ${daysRemaining} days

Action Required: Please review and renew this ${itemType.toLowerCase()} before it expires to ensure compliance.

---
This is an automated notification from SLMS.
    `;

    return this.sendEmail({
      to,
      subject,
      text,
      html,
    });
  }

  async verifyConnection(): Promise<boolean> {
    try {
      await this.transporter.verify();
      this.logger.log('SMTP connection verified');
      return true;
    } catch (error) {
      this.logger.error('SMTP connection failed:', error);
      return false;
    }
  }
}
