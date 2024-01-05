import r from 'rethinkdb';
import postgres from 'postgres';
import { v4 as uuidV4 } from 'uuid';

const sql = postgres({
	host: 'localhost',
	username: 'postgres',
	password: 'postgres',
	port: 5432
});

// Assign static UUIDs to usernames so the can be referenced during import
const usernameMap = {
	'dustin.oreilly': '5af08d90-6dac-434f-8dbe-c7aa76336eaa',
	'joe.furfaro': 'e7464b21-e7b1-4e85-b908-afcf4b21baaf',
	'mike.misselwitz': 'f1187b20-9b82-42e9-8ff5-08a36691b25c',
	'carlos.garcia': '033aad9d-8b11-43a5-8062-beed41c73769',
	'jeff.walsh': '50ba95ea-4ca2-4a68-ab26-e359b529b046',
	'mike.sasaki': '87649d5a-6ab0-4f12-9ea7-39c6c4ed7cdb',
	'nick.cantelmi': '676afc36-6728-4dca-b189-f2373e943829',
	'ty.dupraw': '11b36568-bf25-482e-b4ae-0935041623cc'
};

const conn = await r.connect({
	db: 'mustachebash'
});

async function migrateUsers() {
	try {
		const users = (await r.table('users').run(conn).then(cursor => cursor.toArray()))
			// only insert manually mapped ids
			.filter(u => usernameMap[u.id])
			.map(u => ({
				id: usernameMap[u.id], // uuid PRIMARY KEY NOT NULL,
				username: u.id, // VARCHAR(128) UNIQUE NOT NULL,
				sub_claim: null, // VARCHAR(128) UNIQUE,
				display_name: u.displayName, // VARCHAR(128) NOT NULL,
				password: null, // VARCHAR(256) NOT NULL,
				refresh_token_id: null, // uuid,
				role: u.role, // user_role NOT NULL,
				// Everyone migrated will log in with google
				authority: 'google', // user_authority NOT NULL,
				status: 'active', // user_status DEFAULT 'active',
				meta: {}
			}));

		await sql`
			INSERT INTO users ${sql(users)}
		`;

		console.log('Users Complete!', users.length);
	} catch(e) {
		console.error(e);
	}
}

async function migrateEvents() {
	try {
		const events = (await r.table('events').run(conn).then(cursor => cursor.toArray()))
			.map(e => ({
				id: e.id, // uuid PRIMARY KEY NOT NULL,
				date: e.date.toISOString(), // TIMESTAMP NOT NULL,
				name: e.name, // VARCHAR(256),
				opening_sales: e.openingSales.toISOString() || null, // TIMESTAMP DEFAULT NOW(),
				sales_enabled: false, // BOOL NOT NULL,
				max_capacity: e.maxCapacity || null, // INT,
				alcohol_revenue: e.alcoholRevenue || null, // NUMERIC,
				budget: e.budget || null, // NUMERIC,
				food_revenue: e.foodRevenue || null, // NUMERIC,
				status: e.status, // event_status,
				// Created does not exist yet
				created: e.updated?.toISOString() || null, // TIMESTAMP DEFAULT NOW(),
				updated: e.updated?.toISOString() || null, // TIMESTAMP DEFAULT NOW(),
				// We're dropping this information for now
				updated_by: null, // uuid,
				meta: {}
			}));

		await sql`
			INSERT INTO events ${sql(events)}
		`;

		console.log('Events Complete!', events.length);
	} catch(e) {
		console.error(e);
	}
}

async function migrateCustomers() {
	try {
		const customers = (
			await r.table('transactions')
				.pluck('firstName', 'lastName', 'email', 'created')
				// Normalize by lowercase
				.group(row => row('email').downcase())
				// Select the earliest transaction by an email
				.min('created')
				.ungroup()
				.orderBy(r.asc(row => row('reduction')('created')))
				.run(conn).then(cursor => cursor.toArray())
		)
			.map(({group: email, reduction: c}) => ({
				email: email.trim(), // VARCHAR(256) UNIQUE NOT NULL,
				id: uuidV4(), // uuid PRIMARY KEY NOT NULL,
				first_name: c.firstName.trim(), // VARCHAR(128) NOT NULL,
				last_name: c.lastName.trim(), // VARCHAR(128) NOT NULL,
				created: c.created, // TIMESTAMP DEFAULT NOW()
				updated: c.created, // TIMESTAMP DEFAULT NOW()
				updated_by: null,
				meta: {} // JSONB
			}));

		// FILTER: dedupe emails and names
		const uniqueCustomersMap = new Map();

		for(const customer of customers) {
			const key = customer.email;
			if(!uniqueCustomersMap.has(key)) {
				uniqueCustomersMap.set(key, customer);
			}
		}

		const uniqueCustomers = [...uniqueCustomersMap.values()];

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(customers.length/2000); i++) {
			await sql`
				INSERT INTO customers ${sql(uniqueCustomers.slice(i*2000, (i + 1)*2000))}
			`;
		}

		console.log('Customers Complete!', uniqueCustomers.length);
	} catch(e) {
		console.error(e);
	}
}

async function migrateProducts() {
	try {
		const products = (
			await r.table('products').run(conn).then(cursor => cursor.toArray())
		)
			.map(p => ({
				id: p.id, // uuid PRIMARY KEY NOT NULL,
				status: p.status, // product_status DEFAULT 'inactive',
				type: p.type, // product_type NOT NULL,
				description: p.description, // VARCHAR(256) NOT NULL,
				name: p.name, // VARCHAR(128) NOT NULL,
				price: p.price, // NUMERIC NOT NULL,
				promo: Boolean(p.promo), // BOOL,
				created: p.created, // TIMESTAMP DEFAULT NOW(),
				// Defaulting to created for migration only
				updated: p.created, // TIMESTAMP DEFAULT NOW(),
				updated_by: null,
				meta: {},
				event_id: p.eventId ?? null, // uuid,
				admission_tier: p.type === 'ticket' ? (p.vip ?  'vip' : 'general') : null, // admission_tier
				max_quantity: p.quantity ?? null // INT
			}));

		await sql`
			INSERT INTO products ${sql(products)}
		`;

		console.log('Products Complete!', products.length);
	} catch(e) {
		console.error(e);
	}
}

async function migratePromos() {
	try {
		const promos = (
			await r.table('promos').run(conn).then(cursor => cursor.toArray())
		)
			.map(p => ({
				id: p.id, // uuid PRIMARY KEY NOT NULL,
				created: p.created, // TIMESTAMP DEFAULT NOW(),
				updated: p.updated, // TIMESTAMP DEFAULT NOW(),
				created_by: usernameMap[p.createdBy], // uuid NOT NULL,
				updated_by: p.updatedBy ? usernameMap[p.updatedBy] : null, // uuid,
				price: p.price, // NUMERIC,
				percent_discount: null, // NUMERIC,
				flat_discount: null, // NUMERIC,
				product_id: p.productId, // uuid NOT NULL,
				recipient_name: p.recipient, // VARCHAR(256),
				status: p.status, // promo_status DEFAULT 'active',
				type: p.quantity > 1 ? 'coupon' : p.type, // promo_type NOT NULL,
				meta: {}
			}));

		await sql`
			INSERT INTO promos ${sql(promos)}
		`;

		console.log('Promos Complete!', promos.length);
	} catch(e) {
		console.error(e);
	}
}

// All of these are sourced from the `transactions` table and share foreign key constraints,
// so they must be migrated together
// Current active keys from `transactions` to migrate:
// [
// "amount" ,
// "braintreeCreatedAt" ,
// "braintreeTransactionId" ,
// "comment" ,
// "created" ,
// "email" ,
// "id" ,
// "order" ,
// "originalTransactionId" , <<<< needs a second import for key mapping
// "paypalTransactionId" ,
// "promoId" ,
// "type" ,
// "updated" ,
// "updatedBy"
// ]
async function migrateTheRestOfTheFuckingOwl() {
	try {
		const customers = await sql`
			SELECT email, id FROM customers
		`;

		// map emails to customer ids
		const customerIdsMap = new Map(customers.map(({email, id}) => [email, id]));

		const owls = (
			await r.table('transactions')
				.filter(r.row.hasFields('originalTransactionId').not())
				.without('firstName', 'lastName', 'transfereeId', 'status')
				.orderBy(r.asc('created'))
				.run(conn).then(cursor => cursor.toArray())
		)
			.reduce((acc, cur) => {
				acc.orders.push({
					id: cur.id, // uuid PRIMARY KEY NOT NULL,
					created: cur.created, // TIMESTAMP DEFAULT NOW(),
					customer_id: customerIdsMap.get(cur.email.toLowerCase().trim()), // uuid NOT NULL,
					promo_id: cur.promoId || null, // uuid,
					amount: cur.amount, // NUMERIC,
					status: 'complete',
					meta: {} // JSONB,
				});

				cur.order.forEach(o => {
					acc.orderItems.push({
						order_id: cur.id, // uuid NOT NULL,
						product_id: o.productId, // uuid NOT NULL,
						quantity: o.quantity // INT NOT NULL,
					});
				});

				acc.transactions.push({
					id: uuidV4(), // uuid PRIMARY KEY NOT NULL,
					created: cur.created, // TIMESTAMP DEFAULT NOW(),
					amount: cur.amount, // NUMERIC,
					// Refunds and voids come later
					type: 'sale', // transaction_type NOT NULL,
					order_id: cur.id, // uuid NOT NULL,
					processor_created_at: cur.braintreeCreatedAt ?? null, // TIMESTAMP,
					processor_transaction_id: cur.braintreeTransactionId || cur.paypalTransactionId || null, // VARCHAR(128),
					processor: cur.braintreeTransactionId
						? 'braintree'
						: cur.paypalTransactionId
							? 'paypal'
							: null, // transaction_processor,
					// This needs to be null for the initial import, since we don't know the id we created yet
					parent_transaction_id: null, // uuid,
					meta: {
						...(cur.comment && {comment: cur.comment})
					} // JSONB
				});

				return acc;
			}, {orders: [], orderItems: [], transactions: []});

		// console.log('Owls Sample!', owls.orders.slice(0, 3), owls.orderItems.slice(0, 3), owls.transactions.slice(0, 3));

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(owls.orders.length/2000); i++) {
			await sql`
				INSERT INTO orders ${sql(owls.orders.slice(i*2000, (i + 1)*2000))}
			`;
		}

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(owls.orderItems.length/2000); i++) {
			await sql`
				INSERT INTO order_items ${sql(owls.orderItems.slice(i*2000, (i + 1)*2000))}
			`;
		}

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(owls.transactions.length/2000); i++) {
			await sql`
				INSERT INTO transactions ${sql(owls.transactions.slice(i*2000, (i + 1)*2000))}
			`;
		}

		console.log('Owls Complete!', '\n\tOrders:', owls.orders.length, '\n\tOrder Items:', owls.orderItems.length, '\n\tTransactions:', owls.transactions.length);
	} catch(e) {
		console.error(e);
	}
}

async function migrateTransfers() {
	try {
		const customers = await sql`
			SELECT email, id FROM customers
		`;

		// map emails to customer ids
		const customerIdsMap = new Map(customers.map(({email, id}) => [email, id]));

		const transfers = (
			await r.table('transactions')
				.filter(r.row.hasFields('originalTransactionId'))
				.without('firstName', 'lastName', 'transfereeId', 'status')
				.orderBy(r.asc('created'))
				.run(conn).then(cursor => cursor.toArray())
		)
			.map(t => ({
				id: t.id, // uuid PRIMARY KEY NOT NULL,
				created: t.created, // TIMESTAMP DEFAULT NOW(),
				amount: null, // NUMERIC,
				customer_id: customerIdsMap.get(t.email.toLowerCase().trim()), // uuid NOT NULL,
				promo_id: t.promoId || null, // uuid,
				parent_order_id: t.originalTransactionId, // uuid,
				status: 'complete',
				meta: {
					...(t.comment && {comment: t.comment})
				} // JSONB
			}));

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(transfers.length/2000); i++) {
			await sql`
				INSERT INTO orders ${sql(transfers.slice(i*2000, (i + 1)*2000))}
			`;
		}

		await sql`
			UPDATE orders
			SET status = 'transferred'
			WHERE id IN ${sql(transfers.map(t => t.parent_order_id))}
		`;

		console.log('Order Transfers Complete!', transfers.length);
	} catch(e) {
		console.error(e);
	}
}

async function migrateGuests() {
	try {
		const guests = (
			await r.table('guests')
				.filter(r.row('transactionId').match('-').not())
				.eqJoin('transactionId', r.table('transactions'), {index: 'braintreeTransactionId'})
				.map(row => row('left').merge({transactionId: row('right')('id')}))
				.union(
					r.table('guests')
						.filter(row => row('transactionId').match('-').not())
						.eqJoin('transactionId', r.db('mustachebash').table('transactions'), {index: 'paypalTransactionId'})
						.map(row => row('left').merge({transactionId: row('right')('id')}))
				)
				.union(
					r.table('guests').filter(row => row('transactionId').match('-'))
				)
				.union(
					r.table('guests').filter(row => row('transactionId').eq('COMPED'))
				)
				.run(conn).then(cursor => cursor.toArray())
		)
			.map(g => ({
				id: g.id, // uuid PRIMARY KEY NOT NULL,
				check_in_time: g.checkedIn || null, // TIMESTAMP,
				created: g.created, // TIMESTAMP DEFAULT NOW(),
				created_by: usernameMap[g.createdBy] ?? null, // uuid,
				created_reason: ['purchase', 'transfer'].includes(g.createdBy) ? g.createdBy : (usernameMap[g.createdBy] ? 'comp' : null), // guest_created_reason NOT NULL,
				event_id: g.eventId, // uuid NOT NULL,
				first_name: g.firstName, // VARCHAR(128) NOT NULL,
				last_name: g.lastName, //  VARCHAR(128) NOT NULL,
				status: g.checkedIn ? 'checked_in' : g.status, // guest_status DEFAULT 'active',
				order_id: g.transactionId !== 'COMPED' ? g.transactionId : null, // uuid,
				updated: g.updated ?? g.created, // TIMESTAMP DEFAULT NOW(),
				updated_by: usernameMap[g.updatedBy] ?? null, // uuid,
				admission_tier: g.vip ? 'vip' : 'general', // admission_tier,
				meta: {
					...(g.notes && {comment: g.notes})
				} // JSONB,
			}));

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(guests.length/2000); i++) {
			await sql`
				INSERT INTO guests ${sql(guests.slice(i*2000, (i + 1)*2000))}
			`;
		}

		console.log('Guests Complete!', guests.length);
	} catch(e) {
		console.error(e);
	}
}

// "created" ,
// "createdBy" ,
// "eventId" ,
// "guestId" ,
// "id" ,
// "status" ,
// "updated" ,
// "updatedBy"

async function migrateTickets() {
	try {
		const tickets = (
			await r.table('tickets')
				.run(conn).then(cursor => cursor.toArray())
		)
			.map(t => ({
				id: t.id, //uuid PRIMARY KEY NOT NULL,
				status: t.status, //ticket_status DEFAULT 'active',
				guest_id: t.guestId, //uuid NOT NULL,
				created: t.created, //TIMESTAMP DEFAULT NOW(),
				updated: t.updated || t.created //TIMESTAMP DEFAULT NOW(),
			}));

		// insert 2000 at a time to prevent parameter errors
		for(let i = 0; i < Math.ceil(tickets.length/2000); i++) {
			await sql`
				INSERT INTO tickets ${sql(tickets.slice(i*2000, (i + 1)*2000))}
			`;
		}

		console.log('Tickets Complete!', tickets.length);
	} catch(e) {
		console.error(e);
	}
}


await migrateUsers();
await migrateEvents();
await migrateCustomers();
await migrateProducts();
await migratePromos();
await migrateTheRestOfTheFuckingOwl();
await migrateTransfers();
await migrateGuests();
await migrateTickets();

conn.close();
sql.end();
