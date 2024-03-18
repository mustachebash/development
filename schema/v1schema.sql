-- For random ticket_seed
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- For UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE user_authority AS ENUM ('google', 'email');
CREATE TYPE user_role AS ENUM ('root', 'admin', 'write', 'read', 'doorman');
CREATE TYPE user_status AS ENUM ('active', 'archived');
CREATE TABLE users (
	id uuid PRIMARY KEY NOT NULL,
	username VARCHAR(128) UNIQUE NOT NULL,
	sub_claim VARCHAR(128) UNIQUE,
	display_name VARCHAR(128) NOT NULL,
	password VARCHAR(256),
	refresh_token_id uuid,
	role user_role NOT NULL,
	authority user_authority NOT NULL,
	status user_status DEFAULT 'active',
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	updated TIMESTAMP NOT NULL DEFAULT NOW(),
	meta JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX ON users (username);


CREATE TABLE refresh_tokens (
	id uuid PRIMARY KEY NOT NULL,
	user_id uuid NOT NULL,
	user_agent TEXT NOT NULL,
	ip VARCHAR(128) NOT NULL,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	last_accessed TIMESTAMP NOT NULL DEFAULT NOW(),

	FOREIGN KEY (user_id) REFERENCES users (id)
);
CREATE INDEX ON refresh_tokens (user_id);


CREATE TYPE event_status AS ENUM ('active', 'archived');
CREATE TABLE events (
	id uuid PRIMARY KEY NOT NULL,
	date TIMESTAMP NOT NULL,
	name VARCHAR(256),
	opening_sales TIMESTAMP DEFAULT NOW(),
	sales_enabled BOOL NOT NULL DEFAULT FALSE,
	max_capacity INT,
	alcohol_revenue NUMERIC,
	budget NUMERIC,
	food_revenue NUMERIC,
	status event_status NOT NULL,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	updated TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_by uuid,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb,

	FOREIGN KEY (updated_by) REFERENCES users (id)
);

CREATE TABLE customers (
	id uuid PRIMARY KEY NOT NULL,
	email VARCHAR(256) UNIQUE NOT NULL,
	first_name VARCHAR(128) NOT NULL,
	last_name VARCHAR(128) NOT NULL,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	updated TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_by uuid,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX ON customers (email);
CREATE INDEX ON customers (last_name);


CREATE TYPE product_status AS ENUM ('active', 'archived', 'inactive');
CREATE TYPE product_type AS ENUM ('ticket', 'donation', 'fee', 'accomodation', 'upgrade', 'bundle-ticket');
CREATE TYPE admission_tier AS ENUM ('general', 'vip', 'sponsor', 'stachepass');
CREATE TABLE products (
	id uuid PRIMARY KEY NOT NULL,
	status product_status DEFAULT 'inactive',
	type product_type NOT NULL,
	description VARCHAR(256) NOT NULL,
	admission_tier admission_tier,
	name VARCHAR(128) NOT NULL,
	price NUMERIC NOT NULL,
	promo BOOL NOT NULL,
	max_quantity INT,
	target_product_id uuid,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	updated TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_by uuid,
	event_id uuid,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb,

	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (event_id) REFERENCES events (id),
	FOREIGN KEY (target_product_id) REFERENCES products (id),

	CONSTRAINT admission_tier_not_null_when_ticket_type CHECK (
        (type != 'ticket') OR (type = 'ticket' AND admission_tier IS NOT NULL)
    ),

    CONSTRAINT admission_tier_not_null_when_upgrade_type CHECK (
        (type != 'upgrade') OR (type = 'upgrade' AND admission_tier IS NOT NULL)
    ),

    CONSTRAINT admission_tier_not_null_when_bundle_ticket_type CHECK (
        (type != 'bundle-ticket') OR (type = 'bundle-ticket' AND admission_tier IS NOT NULL)
    ),

    CONSTRAINT target_product_id_not_null_when_upgrade_type CHECK (
        (type != 'upgrade') OR (type = 'upgrade' AND target_product_id IS NOT NULL)
    ),

    CONSTRAINT target_product_id_not_null_when_bundle_ticket_type CHECK (
        (type != 'bundle-ticket') OR (type = 'bundle-ticket' AND target_product_id IS NOT NULL)
    ),

    -- Upgrades target an existing ticket, so an event id is not needed
    CONSTRAINT event_id_not_null_when_bundle_ticket_type CHECK (
        (type != 'bundle-ticket') OR (type = 'bundle-ticket' AND event_id IS NOT NULL)
    ),

    CONSTRAINT event_id_not_null_when_ticket_or_accomodation_type CHECK (
        (type NOT IN ('ticket', 'accomodation')) OR (type IN ('ticket', 'accomodation') AND event_id IS NOT NULL)
    )
);
CREATE INDEX ON products (event_id);


CREATE TYPE promo_status AS ENUM ('active', 'claimed', 'disabled');
CREATE TYPE promo_type AS ENUM ('single-use', 'coupon');
CREATE TABLE promos (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	updated TIMESTAMP NOT NULL DEFAULT NOW(),
	created_by uuid NOT NULL,
	updated_by uuid,
	price NUMERIC,
	percent_discount NUMERIC,
	flat_discount NUMERIC,
	product_id uuid NOT NULL,
	product_quantity INT,
	recipient_name VARCHAR(256),
	status promo_status DEFAULT 'active',
	type promo_type NOT NULL,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb,

	FOREIGN KEY (created_by) REFERENCES users (id),
	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (product_id) REFERENCES products (id),

	CONSTRAINT chk_only_one_is_not_null CHECK (num_nonnulls(price, percent_discount, flat_discount) = 1),
	CONSTRAINT product_quantity_not_null_when_single_use CHECK (
        (type != 'single-use' AND product_quantity IS NULL) OR (type = 'single-use' AND product_quantity IS NOT NULL)
    )
);
CREATE INDEX ON promos (product_id);
COMMENT ON COLUMN promos.product_quantity IS 'If a single-use promo, how many of the product_id to include in the order';


CREATE TYPE order_status AS ENUM ('complete', 'canceled', 'transferred');
CREATE TABLE orders (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	customer_id uuid NOT NULL,
	promo_id uuid,
	amount NUMERIC,
	parent_order_id uuid,
	status order_status NOT NULL,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb,

	FOREIGN KEY (parent_order_id) REFERENCES orders (id),
	FOREIGN KEY (customer_id) REFERENCES customers (id),
	FOREIGN KEY (promo_id) REFERENCES promos (id)
);
CREATE INDEX ON orders (customer_id);
COMMENT ON COLUMN orders.amount IS 'The total amount of money for all items in this specific order. It will be null for transfers.';
COMMENT ON COLUMN orders.parent_order_id IS 'The original order of which a subsequent transfer has been made from';


CREATE TABLE order_items (
	order_id uuid NOT NULL,
	product_id uuid NOT NULL,
	quantity INT NOT NULL,

	FOREIGN KEY (order_id) REFERENCES orders (id),
	FOREIGN KEY (product_id) REFERENCES products (id)
);
CREATE INDEX ON order_items (order_id, product_id);
CREATE INDEX ON order_items (order_id);
CREATE INDEX ON order_items (product_id);


CREATE TYPE transaction_type AS ENUM ('sale', 'refund', 'void');
CREATE TYPE transaction_processor AS ENUM ('braintree', 'paypal');
CREATE TABLE transactions (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	amount NUMERIC,
	type transaction_type NOT NULL,
	order_id uuid NOT NULL,
	processor_created_at TIMESTAMP,
	processor_transaction_id VARCHAR(128),
	processor transaction_processor,
	parent_transaction_id uuid,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb,

	FOREIGN KEY (parent_transaction_id) REFERENCES transactions (id),
	FOREIGN KEY (order_id) REFERENCES orders (id)
);
CREATE INDEX ON transactions (order_id);
CREATE INDEX ON transactions (parent_transaction_id);
COMMENT ON COLUMN transactions.amount IS 'The amount of money charged or credited in this specific transaction by the processor. It might not equal the related order amount.';
COMMENT ON COLUMN transactions.parent_transaction_id IS 'The original transaction of which subsequent refunds or voids have been based on';


CREATE TYPE guest_status AS ENUM ('active', 'archived', 'checked_in');
CREATE TYPE guest_created_reason AS ENUM ('purchase', 'comp', 'transfer');
CREATE TABLE guests (
	id uuid PRIMARY KEY NOT NULL,
	check_in_time TIMESTAMP,
	created TIMESTAMP NOT NULL DEFAULT NOW(),
	created_by uuid,
	created_reason guest_created_reason NOT NULL,
	event_id uuid NOT NULL,
	first_name VARCHAR(128) NOT NULL,
	last_name  VARCHAR(128) NOT NULL,
	status guest_status DEFAULT 'active',
	admission_tier admission_tier NOT NULL,
	order_id uuid,
	ticket_seed VARCHAR(128) NOT NULL UNIQUE,
	updated TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_by uuid,
	meta JSONB NOT NULL DEFAULT '{}'::jsonb,

	FOREIGN KEY (event_id) REFERENCES events (id),
	FOREIGN KEY (created_by) REFERENCES users (id),
	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (order_id) REFERENCES orders (id),

	CONSTRAINT order_id_not_null_when_purchase_reason CHECK (
        (created_reason = 'comp' AND order_id IS NULL) OR (created_reason IN ('purchase', 'transfer') AND order_id IS NOT NULL)
    )
);
CREATE INDEX ON guests (event_id);
CREATE INDEX ON guests (order_id);
CREATE INDEX ON guests (last_name);
-- ticket_seed index is for lookup use when the value is used as a revokable plaintext identifier as opposed to cryptographic seed
CREATE INDEX ON guests (ticket_seed);
COMMENT ON COLUMN guests.ticket_seed IS 'The random string used to generate the QR code for this guests ticket. Resetting this seed will disable any existing QR codes.';
