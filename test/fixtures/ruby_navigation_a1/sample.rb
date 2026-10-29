# Synthetic source: parsed, never executed.
module Alpha
  class Worker
    def perform
      :alpha
    end
  end
end
module Beta
  class Worker
    def perform
      :beta
    end
  end
end
class Child < Alpha::Worker
  def report
    perform
  end
end
Alpha::Worker.new.perform
Beta::Worker.new.perform
receiver.public_send(method_name)
MissingPilotConstant
