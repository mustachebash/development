CREATE TYPE user_role AS ENUM ('root', 'admin', 'read', 'doorman');
CREATE TYPE user_status AS ENUM ('active', 'archived');
CREATE TABLE users (
	id uuid PRIMARY KEY NOT NULL,
	username VARCHAR(128) NOT NULL,
	display_name VARCHAR(128) NOT NULL,
	password VARCHAR(256) NOT NULL,
	refresh_token_id uuid,
	role user_role NOT NULL,
	status user_status DEFAULT 'active',
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW()
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
	status event_status,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,

	FOREIGN KEY (updated_by) REFERENCES users (id)
);


CREATE TYPE site_status AS ENUM ('active', 'archived');
CREATE TABLE sites (
	id uuid PRIMARY KEY NOT NULL,
	domain VARCHAR(128) NOT NULL,
	settings JSONB,
	status site_status DEFAULT 'active',
	current_event_id uuid,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,

	FOREIGN KEY (current_event_id) REFERENCES events (id),
	FOREIGN KEY (updated_by) REFERENCES users (id)
);
CREATE INDEX ON sites (domain);


CREATE TABLE customers (
	id uuid PRIMARY KEY NOT NULL,
	email VARCHAR(256) UNIQUE NOT NULL,
	first_name VARCHAR(128) NOT NULL,
	last_name VARCHAR(128) NOT NULL
);
CREATE INDEX ON customers (email);
CREATE INDEX ON customers (last_name);


CREATE TYPE product_status AS ENUM ('active', 'archived', 'inactive');
CREATE TYPE product_type AS ENUM ('ticket', 'donation', 'fee');
CREATE TABLE products (
	id uuid PRIMARY KEY NOT NULL,
	status product_status DEFAULT 'inactive',
	type product_type NOT NULL,
	description VARCHAR(256) NOT NULL,
	name VARCHAR(128) NOT NULL,
	price NUMERIC NOT NULL,
	promo BOOL,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,
	event_id uuid,

	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (event_id) REFERENCES events (id)
);
CREATE INDEX ON products (event_id);


CREATE TYPE promo_status AS ENUM ('active', 'claimed', 'disabled');
CREATE TYPE promo_type AS ENUM ('single-use');
CREATE TABLE promos (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	updated TIMESTAMP DEFAULT NOW(),
	created_by uuid NOT NULL,
	updated_by uuid,
	email VARCHAR(256),
	price NUMERIC NOT NULL,
	product_id uuid NOT NULL,
	recipient VARCHAR(256) NOT NULL,
	status promo_status DEFAULT 'active',
	type promo_type NOT NULL,

	FOREIGN KEY (created_by) REFERENCES users (id),
	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (product_id) REFERENCES products (id)
);
CREATE INDEX ON promos (product_id);


CREATE TYPE order_status AS ENUM ('complete', 'canceled');
CREATE TABLE orders (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	customer_id uuid NOT NULL,
	amount NUMERIC,

	FOREIGN KEY (customer_id) REFERENCES customers (id)
);
CREATE INDEX ON orders (customer_id);


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


CREATE TYPE transaction_type AS ENUM ('sale', 'refund', 'transfer');
CREATE TABLE transactions (
	id uuid PRIMARY KEY NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	amount NUMERIC,
	type transaction_type NOT NULL,
	order_id uuid NOT NULL,
	braintree_created_at TIMESTAMP,
	braintree_transaction_id VARCHAR(128),
	original_transaction_id uuid,

	FOREIGN KEY (original_transaction_id) REFERENCES transactions (id),
	FOREIGN KEY (order_id) REFERENCES orders (id)
);
CREATE INDEX ON transactions (order_id);
CREATE INDEX ON transactions (original_transaction_id);
COMMENT ON COLUMN transactions.original_transaction_id IS 'The original transaction of which subsequent refunds or transfers have been based on';


CREATE TYPE guest_status AS ENUM ('active', 'consumed', 'disabled');
CREATE TYPE guest_created_reason AS ENUM ('purchase', 'comp');
CREATE TABLE guests (
	id uuid PRIMARY KEY NOT NULL,
	checked_in BOOL,
	check_in_time TIMESTAMP,
	created TIMESTAMP DEFAULT NOW(),
	created_by uuid NOT NULL,
	created_reason guest_created_reason NOT NULL,
	event_id uuid NOT NULL,
	first_name VARCHAR(128) NOT NULL,
	last_name  VARCHAR(128) NOT NULL,
	status guest_status DEFAULT 'active',
	order_id uuid,
	updated TIMESTAMP DEFAULT NOW(),
	updated_by uuid,

	FOREIGN KEY (event_id) REFERENCES events (id),
	FOREIGN KEY (created_by) REFERENCES users (id),
	FOREIGN KEY (updated_by) REFERENCES users (id),
	FOREIGN KEY (order_id) REFERENCES orders (id)
);
CREATE INDEX ON guests (event_id);
CREATE INDEX ON guests (order_id);
CREATE INDEX ON guests (last_name);


CREATE TYPE ticket_status AS ENUM ('active', 'consumed', 'disabled');
CREATE TYPE ticket_created_reason AS ENUM ('purchase', 'comp');
CREATE TABLE tickets (
	id uuid PRIMARY KEY NOT NULL,
	status ticket_status DEFAULT 'active',
	guest_id uuid NOT NULL,
	created TIMESTAMP DEFAULT NOW(),
	created_by uuid NOT NULL,
	created_reason ticket_created_reason NOT NULL,
	updated TIMESTAMP DEFAULT NOW(),

	FOREIGN KEY (guest_id) REFERENCES guests (id)
);
CREATE INDEX ON tickets (guest_id);
