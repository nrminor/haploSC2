#!/usr/bin/env nextflow

nextflow.enable.dsl = 2



// WORKFLOW SPECIFICATION
// --------------------------------------------------------------- //
workflow {
	
	
	// input channels
	ch_reads = Channel
        .fromFilePairs( "${params.fastq_dir}/*{_R1,_R2}_001.fastq.gz", flat: true )

    ch_primer_bed = Channel
        .fromPath( params.primer_bed )
	
	// Workflow steps
    GET_PRIMER_SEQS (
        ch_primer_bed
    )
    
    TRIM_TO_MATCHED_PRIMERS (
        ch_reads,
        GET_PRIMER_SEQS.out
    )

    MERGE_PAIRS (
        TRIM_TO_MATCHED_PRIMERS.out
    )

    CLUMP_READS (
        MERGE_PAIRS.out.merged
    )

    MAP_TO_REF (
        CLUMP_READS.out
    )

    EXTRACT_AMPLICON (
        MAP_TO_REF.out
    )

    BAM_TO_FASTQ (
        EXTRACT_AMPLICON.out
    )

    FILTER_BY_LENGTH (
        BAM_TO_FASTQ.out
    )

    HAPLOTYPE_ASSEMBLY (
        FILTER_BY_LENGTH.out
    )

    // RECORD_FREQUENCIES (
    //     HAPLOTYPE_ASSEMBLY.out
    // )

    DOWNSAMPLE_ASSEMBLIES (
        HAPLOTYPE_ASSEMBLY.out
    )

    MAP_TO_REF2 (
        DOWNSAMPLE_ASSEMBLIES.out
    )

    if ( params.primer_bed ) {

        TRIM_PRIMERS (
            MAP_TO_REF2.out
        )

        CALL_CONSENSUS_SEQS (
            TRIM_PRIMERS.out
        )
    } else {

        CALL_CONSENSUS_SEQS (
            MAP_TO_REF2.out
        )

    }

    CALL_VARIANTS (
        MAP_TO_REF2.out
    )

    // GENERATE_REPORT (
    //     DOWNSAMPLE_ASSEMBLIES.out,
    //     MAP_TO_REF2.out,
    //     CALL_CONSENSUS_SEQS.out,
    //     CALL_VARIANTS.out
    // )
	
	
}
// --------------------------------------------------------------- //



// DERIVATIVE PARAMETER SPECIFICATION
// --------------------------------------------------------------- //
// Additional parameters that are derived from parameters set in nextflow.config

// --------------------------------------------------------------- //




// PROCESS SPECIFICATION 
// --------------------------------------------------------------- //

process GET_PRIMER_SEQS {

    /*
    */

    label "general"

    input:
    path bed_file

    output:
    path "*.fasta"

    script:
    """
    bedtools getfasta -fi ${params.reference} -bed ${bed_file} -fo primer_seqs.fasta
    """

}

process TRIM_TO_MATCHED_PRIMERS {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus params.available_cpus
	
	input:
	tuple val(sample_id), path(reads1), path(reads2)
    path primer_fasta
	
	output:
    tuple val(sample_id), path("*reads1.fastq.gz"), path("*reads2.fastq.gz")
	
	script:
	"""
	ampl-BBDuk.py \
    --primer_fasta ${primer_fasta} \
    --in_path ${reads1} \
    --in2_path ${reads2} \
    --outm amplicon_reads1.fastq.gz \
    --outm2 amplicon_reads1.fastq.gz
	"""
}

process MERGE_PAIRS {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus params.available_cpus
	
	input:
	tuple val(sample_id), path(reads1), path(reads2)
	
	output:
    tuple val(sample_id), path("*_merged.fastq.gz"), emit: merged
    path "*_unmerged.fastq.gz", emit: unmerged
	
	script:
	"""
    bbmerge.sh in1=${reads1} in2=${reads2} \
    out=${sample_id}_merged.fastq.gz outu=${sample_id}_unmerged.fastq.gz \
    t=${task.cpus}
	"""
}

process CLUMP_READS {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus params.available_cpus
	
	input:
	tuple val(sample_id), path(reads)
	
	output:
    tuple val(sample_id), path("*.fastq.gz")
	
	script:
	"""
	clumpify.sh in=${reads} out=${sample_id}_clumped.fastq.gz t=${task.cpus} reorder
	"""
}

process MAP_TO_REF {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus params.available_cpus
	
	input:
	tuple val(sample_id), path(reads)
	
	output:
	tuple val(sample_id), path("*.bam"), path("*.bam.bai")
	
	script:
    if ( params.geneious_mode == true )
        """
        geneious -i ${params.reference} ${reads} -operation Map_to_Reference -o ${sample_id}.bam
        """
    else
        """
        bbmap.sh ref=${params.reference} in=${reads} out=stdout.sam t=${task.cpus} | \
        samtools sort -o ${sample_id}_sorted.bam - && \
        samtools index -o ${sample_id}_sorted.bam.bai ${sample_id}_sorted.bam
        """
}

process TRIM_TO_AMPLICONS {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), stdin
	
	output:
    tuple val(sample_id), path("*sorted_clipped.bam"), path("*sorted_clipped.bam.bai")
	
	script:
	"""
    samtools sort -o ${sample_id}_sorted.bam - && \
    samtools index -o ${bam}_sorted.bai ${sample_id}_sorted.bam && \
	samtools ampliconclip -b ${params.primer_bed} ${sample_id}_sorted.bam -o ${sample_id}_clipped.bam
	"""
}

process EXTRACT_AMPLICON {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(bam), path(index)
	
	output:
    tuple val(sample_id), path("*.bam")
	
	script:
	"""
    grep ${params.desired_amplicon} ${params.primer_bed} > amplicon-primers.bed && \
    bedtools merge -d 300 -i amplicon-primers.bed > amplicon-only.bed && \
    bedtools intersect -a ${bam} -b amplicon-only.bed > ${sample_id}_extracted_reads.bam
    """
}

process BAM_TO_FASTQ {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus params.available_cpus
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.fastq.gz")
	
	script:
	"""
	reformat.sh in=${bam} out=stdout.fastq.gz t=${task.cpus} | \
	clumpify.sh in=stdin.fastq.gz out=${sample_id}_amplicon_reads.fastq.gz t=${task.cpus} reorder
	"""
}

process FILTER_BY_LENGTH {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(reads)
	
	output:
	tuple val(sample_id), path("*.fastq.gz")
	
	script:
	"""
	filter-by-amplicon-length.py ${reads} ${params.primer_bed} ${params.desired_amplicon} \
    | gzip -c > ${sample_id}_filtered.fastq.gz
	"""
}

process HAPLOTYPE_ASSEMBLY {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 8
	
	input:
	tuple val(sample_id), path(reads)
	
	output:
	tuple val(sample_id), path(bam)
	
	script:
    if ( params.geneious_mode == true )
        """
        geneious -i ${reads} –operation de_novo_assemble -x ${params.assembly_profile} -o ${sample_id}.bam
        """
    else
        """
        spades.py --merged ${reads} --corona --threads ${task.cpus} -o .
        """
}

// process RECORD_FREQUENCIES {

//     /*
//     */
	
// 	tag "${sample_id}"
//    label "general"
// 	publishDir params.results, mode: 'copy'
	
// 	input:
	
	
// 	output:
	
	
// 	script:
// 	"""
	
// 	"""
// }

process DOWNSAMPLE_ASSEMBLIES {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.bam")
	
	script:
	"""
	samtools view -b -s 0.1 ${bam} > ${sample_id}_downsampled.bam
	"""
}

process MAP_TO_REF2 {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.bam")
	
	script:
	if ( params.geneious_mode == true )
        """
        echo in development > false.bam
        """
    else
        """
        reformat.sh in=${bam} out=stdout.fastq.gz | \
        bbmap.sh ref=${params.reference} in=${reads} out=stdout.sam | \
        reformat.sh in=stdin.sam out=${sample_id}.bam 
        """
}

process TRIM_PRIMERS {

    /*
    */
	
	tag "${sample_id}"
    label "iVar"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.bam")
	
	script:
	"""
    ivar trim -b ${params.primer_bed} -p sample_id_trimmed -i ${bam} -q 15 -m 50 -s 4
	"""
}

process CALL_CONSENSUS_SEQS {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.fasta")
	
	script:
	"""
    pileup.sh in=${bam} out=${sample_id}_pileup.txt consensus=${sample_id}_consensus.fasta
	"""
}

process CALL_VARIANTS {

    /*
    */
	
	tag "${sample_id}"
    label "general"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.vcf")
	
	script:
	"""
    bcftools mpileup -Ou -f ${params.reference} ${bam} | bcftools call -mv -Ov -o ${sample_id}.vcf
	"""

}

process RUN_IVAR {

    /*
    */
	
	tag "${sample_id}"
    label "iVar"
	publishDir params.results, mode: 'copy'

    cpus 3
	
	input:
	tuple val(sample_id), path(bam)
	
	output:
	tuple val(sample_id), path("*.tsv"), path("*.fasta")
	
	script:
	"""
    samtools mpileup -aa -A -d 600000 -B -Q 0 ${bam} | \
    tee >(ivar variants -p ${sample_id} -q 20 -t 0.03 -r ${params.reference} -g ${params.gff}) | \
    ivar consensus -p ${sample_id}_ivar_consensus -q 20 -t 0
	"""

}

// process GENERATE_REPORT {
	
// 	// This process does something described here
	
// 	tag "${sample_id}"
// 	publishDir params.results, mode: 'copy'
	
// 	memory 1.GB
// 	cpus 1
// 	time '10minutes'
	
// 	input:
	
	
// 	output:
	
	
// 	when:
	
	
// 	script:
// 	"""
	
// 	"""
// }

// --------------------------------------------------------------- //