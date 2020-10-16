import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException
} from '@nestjs/common';
import { UserPayload } from '../auth/get-user.decorator';
import { CreateReservationDto, CreateReservationProductDto } from './reservation.dto';
import { CreateDocumentDefinition, Model, Types } from 'mongoose';
import { Reservation } from './reservation.schema';
import { InjectModel } from '@nestjs/mongoose';
import { UsersService } from '../users/users.service';
import { Product } from '../products/product.schema';
import { Ticket } from '../seats/ticket.schema';
import { checkCompletedLogin } from '../common/utils';
import { Seat } from '../seats/seat.schema';
import { Stripe } from 'stripe';
import { AppGateway } from '../socket/app.gateway';
import { PromotionsService } from '../promotions/promotions.service';
import { Promotion } from '../promotions/promotion.schema';
import { User } from '../users/user.schema';
import { NotificationsService } from '../notifications/notifications.service';

@Injectable()
export class ReservationsService {
  private readonly logger = new Logger('ReservationsService');

  constructor(
      @InjectModel(Reservation.name) private readonly reservationModel: Model<Reservation>,
      @InjectModel(Product.name) private readonly productModel: Model<Product>,
      @InjectModel(Ticket.name) private readonly ticketModel: Model<Ticket>,
      private readonly usersService: UsersService,
      private readonly appGateway: AppGateway,
      private readonly promotionsService: PromotionsService,
      private readonly notificationsService: NotificationsService,
  ) {}

  async createReservation(
      userPayload: UserPayload,
      dto: CreateReservationDto,
  ): Promise<Reservation> {
    this.logger.debug(`createReservation: ${JSON.stringify(dto)}`);

    const user = checkCompletedLogin(userPayload);
    this.logger.debug(`[1] completed login`);

    const products = await this.checkProduct(dto.products);
    this.logger.debug(`[2] check product`);

    const card = await this.usersService.getCardById(userPayload, dto.pay_card_id);
    this.logger.debug(`[3] check card`);

    const ticketIds = dto.ticket_ids.map(id => new Types.ObjectId(id));
    const tickets = await this.checkSeats(ticketIds);
    this.logger.debug(`[4] check tickets`);

    const original_price = ReservationsService.calculateOriginalPrice(products, tickets);
    const { total_price, promotion } = await this.applyPromotionIfNeeded(original_price, dto.promotion_id, user);
    this.logger.debug(`[5] ${dto.promotion_id} ${original_price} -> ${total_price}`);

    const paymentIntent = await this.usersService.charge(
        card,
        total_price,
        'vnd',
    );
    this.logger.debug(`[6] charged`);

    const reservation = await this.saveAndUpdate({
      dto,
      total_price,
      user,
      paymentIntent,
      ticketIds,
      promotion,
      original_price,
    });
    const data: Record<string, Reservation> = ticketIds.reduce(
        (acc, e) => ({
          ...acc,
          [e.toHexString()]: reservation,
        }),
        {},
    );
    this.appGateway.server
        .to(`reservation:${dto.show_time_id}`)
        .emit('reserved', data);

    this.notificationsService
        .pushNotification(user, reservation._id)
        .catch((e) => this.logger.debug(`Push notification error: ${e}`));

    this.logger.debug(`[8] returns...`);
    return reservation;
  }

  private static calculateOriginalPrice(products: { product: Product; quantity: number }[], tickets: Ticket[]) {
    return tickets.reduce((acc, e) => acc + e.price, 0) +
        products.reduce((acc, e) => acc + e.product.price * e.quantity, 0);
  }

  private async saveAndUpdate(
      info: {
        dto: CreateReservationDto,
        total_price: number,
        user: User,
        paymentIntent: Stripe.PaymentIntent,
        ticketIds: any[],
        promotion: Promotion | null,
        original_price: number,
      }
  ): Promise<Reservation> {
    const { dto, original_price, paymentIntent, user, total_price, ticketIds, promotion } = info;

    const session = await this.ticketModel.db.startSession();
    try {
      session.startTransaction();

      const doc: Omit<CreateDocumentDefinition<Reservation>, '_id'> = {
        email: dto.email,
        is_active: true,
        original_price,
        phone_number: dto.phone_number,
        products: dto.products.map(p => ({
          id: new Types.ObjectId(p.product_id),
          quantity: p.quantity,
        })),
        total_price,
        show_time: new Types.ObjectId(dto.show_time_id),
        user: user._id,
        payment_intent_id: paymentIntent.id,
      };
      let reservation = await this.reservationModel.create(
          [doc],
          { session },
      ).then(v => v[0]);

      for (const id of ticketIds) {
        const updated = await this.ticketModel.findOneAndUpdate(
            { _id: id, reservation: null },
            { reservation: reservation._id },
            { session },
        );
        if (!updated) {
          throw new Error(`Ticket already reserved`);
        }
      }

      if (promotion) {
        await this.promotionsService.markUsed(promotion, user);
      }

      reservation = await reservation.populate('user').execPopulate();

      await session.commitTransaction();
      session.endSession();

      this.logger.debug(`[7] done ${JSON.stringify(reservation)}`);
      return reservation;
    } catch (e) {
      await session.abortTransaction();
      session.endSession();

      this.logger.debug(`[7] error ${e}`);
      throw new UnprocessableEntityException(e.message ?? `Cannot create reservation`);
    }
  }

  private async checkProduct(products: CreateReservationProductDto[]): Promise<{ product: Product; quantity: number }[]> {
    const productWithQuantity: { product: Product, quantity: number }[] = [];

    for (const p of products) {
      const product = await this.productModel.findById(p.product_id);
      if (!product) {
        throw new NotFoundException(`Not found product with id: ${p.product_id}`);
      }
      productWithQuantity.push({ product, quantity: p.quantity });
    }

    return productWithQuantity;
  }

  private async checkSeats(ticketIds: any[]): Promise<Ticket[]> {
    // const invalidTickets = await this.ticketModel.find({
    //   $and: [
    //     { _id: { $in: ticketIds } },
    //     { reservation: { $ne: null } },
    //   ]
    // }).populate('seat');

    const tickets = await this.ticketModel.find({ _id: { $in: ticketIds } }).populate('seat');
    const invalidTickets = tickets.filter(t => !!t.reservation);

    if (invalidTickets.length > 0) {
      const seats = invalidTickets.map(t => {
        const seat = (t.seat as Seat);
        return `${seat.row}${seat.column}`;
      }).join(', ');

      throw new UnprocessableEntityException(`Tickets already reserved: ${seats}`);
    }

    return tickets;
  }

  private async applyPromotionIfNeeded(
      original_price: number,
      promotion_id: string | null | undefined,
      user: User
  ): Promise<{ total_price: number; promotion: Promotion | null }> {
    let total_price = original_price;
    let promotion: Promotion | null = null;

    if (promotion_id) {
      promotion = await this.promotionsService.checkValid(promotion_id, user);

      if (promotion) {
        total_price = total_price * (1 - promotion.discount);
      } else {
        throw new BadRequestException('Invalid promotion');
      }
    }

    return { total_price: Math.ceil(total_price), promotion };
  }
}
