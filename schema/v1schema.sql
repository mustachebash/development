CREATE TYPE user_authority AS ENUM ('google', 'email');
CREATE TYPE user_role AS ENUM ('root', 'admin', 'read', 'doorman');
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
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	meta JSONB
);
CREATE INDEX ON users (username);


CREATE TYPE event_status AS ENUM ('active', 'archived');
CREATE TABLE events (
	id uuid PRIMARY KEY NOT NULL,
	date TIMESTAMP NOT NULL,
	name VARCHAR(256),
	opening_sales TIMESTAMP DEFAULT NOW(),
	sales_enabled BOOL NOT NULL,
	max_capacity INT,
	alcohol_revenue NUMERIC,
	budget NUMERIC,
	food_revenue NUMERIC,
	status event_status NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,
	meta JSONB,

	FOREIGN KEY (updated_by) REFERENCES users (id)
);

-- Probably don't need these anymore?
-- CREATE TYPE site_status AS ENUM ('active', 'archived');
-- CREATE TABLE sites (
-- 	id uuid PRIMARY KEY NOT NULL,
-- 	domain VARCHAR(128) NOT NULL,
-- 	settings JSONB,
-- 	status site_status DEFAULT 'active',
-- 	current_event_id uuid,
-- 	created TIMESTAMP DEFAULT NOW(),
-- 	updated TIMESTAMP DEFAULT NOW(),
-- 	updated_by uuid,

-- 	FOREIGN KEY (current_event_id) REFERENCES events (id),
-- 	FOREIGN KEY (updated_by) REFERENCES users (id)
-- );
-- CREATE INDEX ON sites (domain);


CREATE TABLE customers (
	id uuid PRIMARY KEY NOT NULL,
	email VARCHAR(256) UNIQUE NOT NULL,
	first_name VARCHAR(128) NOT NULL,
	last_name VARCHAR(128) NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,
	meta JSONB
);
CREATE INDEX ON customers (email);
CREATE INDEX ON customers (last_name);


CREATE TYPE product_status AS ENUM ('active', 'archived', 'inactive');
CREATE TYPE product_type AS ENUM ('ticket', 'donation', 'fee', 'accomodation');
CREATE TYPE admission_tier AS ENUM ('general', 'vip', 'sponsor');
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
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,
	event_id uuid,
	meta JSONB,

	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (event_id) REFERENCES events (id),

	CONSTRAINT admission_tier_not_null_when_ticket_type CHECK (
        (type != 'ticket' AND admission_tier IS NULL) OR (type = 'ticket' AND admission_tier IS NOT NULL)
    )
);
CREATE INDEX ON products (event_id);


CREATE TYPE promo_status AS ENUM ('active', 'claimed', 'disabled');
CREATE TYPE promo_type AS ENUM ('single-use', 'coupon');
CREATE TABLE promos (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	created_by uuid NOT NULL,
	updated_by uuid,
	price NUMERIC,
	percent_discount NUMERIC,
	flat_discount NUMERIC,
	product_id uuid NOT NULL,
	recipient_name VARCHAR(256),
	status promo_status DEFAULT 'active',
	type promo_type NOT NULL,
	meta JSONB,

	FOREIGN KEY (created_by) REFERENCES users (id),
	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (product_id) REFERENCES products (id),

	CONSTRAINT chk_only_one_is_not_null CHECK (num_nonnulls(price, percent_discount, flat_discount) = 1)
);
CREATE INDEX ON promos (product_id);


CREATE TYPE order_status AS ENUM ('complete', 'canceled', 'transferred');
CREATE TABLE orders (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	customer_id uuid NOT NULL,
	promo_id uuid,
	amount NUMERIC,
	parent_order_id uuid,
	status order_status NOT NULL,
	meta JSONB,

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
	created TIMESTAMP DEFAULT NOW(),
	amount NUMERIC,
	type transaction_type NOT NULL,
	order_id uuid NOT NULL,
	processor_created_at TIMESTAMP,
	processor_transaction_id VARCHAR(128),
	processor transaction_processor,
	parent_transaction_id uuid,
	meta JSONB,

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
	created TIMESTAMP DEFAULT NOW(),
	created_by uuid,
	created_reason guest_created_reason NOT NULL,
	event_id uuid NOT NULL,
	first_name VARCHAR(128) NOT NULL,
	last_name  VARCHAR(128) NOT NULL,
	status guest_status DEFAULT 'active',
	admission_tier admission_tier NOT NULL,
	order_id uuid,
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,
	meta JSONB,

	FOREIGN KEY (event_id) REFERENCES events (id),
	FOREIGN KEY (created_by) REFERENCES users (id),
	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (order_id) REFERENCES orders (id)
);
CREATE INDEX ON guests (event_id);
CREATE INDEX ON guests (order_id);
CREATE INDEX ON guests (last_name);


CREATE TYPE ticket_status AS ENUM ('active', 'consumed', 'disabled');
CREATE TABLE tickets (
	id uuid PRIMARY KEY NOT NULL,
	status ticket_status DEFAULT 'active',
	guest_id uuid NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),

	FOREIGN KEY (guest_id) REFERENCES guests (id)
);
CREATE INDEX ON tickets (guest_id);
