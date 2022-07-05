from memori import Pipeline  # note this Stage/Pipeline is different than the one in app/helpers.py


class DCANPipeline(Pipeline):
    """DCANPipeline is a modified memori.pipeline class with extensions for DCAN integration

    This class extends the memori.pipeline class so it can be integrated with the DCAN pipeline/stage
    style of processing.

    Because the term Stage/Pipeline is used in both DCAN/memori designs, it can be
    confusing to distinguish the two. From here on, we will refer to each with the prefix
    dcan_ or memori_ to avoid confusion.

    In DCAN processing, a dcan_Stage is a pipeline, refering
    to an individual processing step (e.g. FreeSurfer processing/FMRI Volume processing).
    Each dcan_Stage wraps a bash script to do it's processing.

    In memori processing, a memori_Stage represents a individual task unit. A number of stages,
    can be combined to form a memori_Pipeline. A memori_Stage wraps a python function
    rather than a bash script. Thus, a memori_Pipeline is the equivalent of a dcan_Stage.

    Each dcan_Stage receives a session spec on construction, and a memori_Pipeline recieves
    a list of memori_Stages on construction. To mimic the dcan_Stage behavior, we need
    to override the __init__ method on the subclassed memori_Pipeline, and call
    the parent memori_Pipeline constructor with the Stages defined inside the subclassed
    DCANPipeline.

    Since the dcan processing identifies dcan_Stages through __class__.__name__
    this class should be subclassed before used, with the desired name for the
    dcan Stage.
    """

    def __str__(self):
        return self.__class__.__name__

    def check_expected_outputs(self):
        """To be implemented."""
        pass

    def deactivate_runtime_calls(self):
        """To be implemented."""
        pass

    def deactivate_check_expected_outputs(self):
        """To be implemented."""
        pass

    def deactivate_remove_expected_outputs(self):
        """To be implemented."""
        pass

    def activate_ignore_expected_outputs(self):
        """To be implemented."""
        pass
