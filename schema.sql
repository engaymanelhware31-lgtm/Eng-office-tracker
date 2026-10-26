-- Initial database schema: Engineering Office Client & Transaction Tracking
-- Database: PostgreSQL
-- Important: office_id is included in all tenant-owned tables.
-- Enable and test Row-Level Security (RLS) before production deployment.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE offices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    license_status VARCHAR(30) NOT NULL DEFAULT 'active'
        CHECK (license_status IN ('active', 'suspended', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID REFERENCES offices(id) ON DELETE RESTRICT,
    full_name VARCHAR(200) NOT NULL,
    email VARCHAR(320) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role VARCHAR(30) NOT NULL
        CHECK (role IN ('platform_admin', 'office_manager', 'employee', 'read_only')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    client_name VARCHAR(200) NOT NULL,
    phone VARCHAR(40),
    email VARCHAR(320),
    address TEXT,
    civil_id_or_company_no VARCHAR(100),
    notes TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (office_id, id)
);

CREATE INDEX idx_clients_office_name ON clients(office_id, client_name);
CREATE INDEX idx_clients_office_phone ON clients(office_id, phone);

CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    client_id UUID NOT NULL,
    project_name VARCHAR(200) NOT NULL,
    project_type VARCHAR(100),
    location TEXT,
    start_date DATE,
    target_end_date DATE,
    status VARCHAR(40) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'on_hold', 'completed', 'cancelled')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (office_id, id),
    FOREIGN KEY (office_id, client_id) REFERENCES clients(office_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_projects_office_client ON projects(office_id, client_id);

CREATE TABLE transaction_statuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    status_name VARCHAR(100) NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_final BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (office_id, status_name),
    UNIQUE (office_id, id)
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    client_id UUID NOT NULL,
    project_id UUID,
    status_id UUID NOT NULL,
    reference_no VARCHAR(100) NOT NULL,
    transaction_type VARCHAR(100) NOT NULL,
    authority VARCHAR(200),
    description TEXT,
    assigned_to UUID,
    submitted_at DATE,
    due_date DATE,
    completed_at DATE,
    priority VARCHAR(20) NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    next_action TEXT,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (office_id, id),
    UNIQUE (office_id, reference_no),
    FOREIGN KEY (office_id, client_id) REFERENCES clients(office_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (office_id, project_id) REFERENCES projects(office_id, id) ON DELETE SET NULL,
    FOREIGN KEY (office_id, status_id) REFERENCES transaction_statuses(office_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (assigned_to) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_transactions_office_status ON transactions(office_id, status_id);
CREATE INDEX idx_transactions_office_due_date ON transactions(office_id, due_date);
CREATE INDEX idx_transactions_office_assignee ON transactions(office_id, assigned_to);
CREATE INDEX idx_transactions_office_client ON transactions(office_id, client_id);

CREATE TABLE transaction_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    transaction_id UUID NOT NULL,
    old_status_id UUID,
    new_status_id UUID,
    update_note TEXT NOT NULL,
    next_action TEXT,
    follow_up_date DATE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (office_id, transaction_id) REFERENCES transactions(office_id, id) ON DELETE CASCADE,
    FOREIGN KEY (office_id, old_status_id) REFERENCES transaction_statuses(office_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (office_id, new_status_id) REFERENCES transaction_statuses(office_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_updates_office_transaction_date
    ON transaction_updates(office_id, transaction_id, created_at DESC);

CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    transaction_id UUID NOT NULL,
    original_file_name VARCHAR(255) NOT NULL,
    storage_key TEXT NOT NULL,
    mime_type VARCHAR(150),
    file_size_bytes BIGINT CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (office_id, transaction_id) REFERENCES transactions(office_id, id) ON DELETE CASCADE
);

CREATE INDEX idx_documents_office_transaction ON documents(office_id, transaction_id);

CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    transaction_id UUID,
    title VARCHAR(250) NOT NULL,
    details TEXT,
    assigned_to UUID,
    due_at TIMESTAMPTZ,
    status VARCHAR(30) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'in_progress', 'done', 'cancelled')),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    FOREIGN KEY (office_id, transaction_id) REFERENCES transactions(office_id, id) ON DELETE CASCADE,
    FOREIGN KEY (assigned_to) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_tasks_office_status_due ON tasks(office_id, status, due_at);

CREATE TABLE licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    license_key_hash TEXT NOT NULL UNIQUE,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    status VARCHAR(30) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'revoked')),
    notes TEXT
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID REFERENCES offices(id) ON DELETE SET NULL,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_office_date ON audit_logs(office_id, created_at DESC);

-- SECURITY NOTE:
-- This schema establishes office_id relationships and composite foreign keys.
-- Production deployment must additionally:
-- 1. Configure and test PostgreSQL RLS policies for every tenant-owned table.
-- 2. Derive office_id from the authenticated server-side session, never trust a
--    client-supplied office_id.
-- 3. Ensure background jobs, exports, file downloads and reports enforce the same
--    tenant boundary.
-- 4. Use a secure password hashing algorithm (Argon2id/bcrypt) in the application.
